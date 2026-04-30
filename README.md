# Copy Fail (CVE-2026-31431) — Kubernetes Container Escape PoC

A proof-of-concept demonstrating how a **fully unprivileged container** can achieve **node-level code execution** on Kubernetes by exploiting the CVE-2026-31431 Linux kernel page-cache corruption bug through shared container image layers.

> **Disclaimer:** This repository is published for educational and defensive purposes only. Use it exclusively on systems you own or have explicit authorization to test.

## Background

CVE-2026-31431 ("Copy Fail") is a Linux kernel vulnerability in the page-cache Copy-on-Write (CoW) path. An `AF_ALG` splice race allows an unprivileged process to corrupt the page-cache pages of a **read-only** file. The corruption persists in the kernel page cache and is visible to every process that subsequently reads or executes the file — including processes in other containers or on the host.

For full details on the original vulnerability, see [copy.fail](https://copy.fail/).

## How It Works

The attack chain has three stages: **page-cache corruption**, **cross-container propagation**, and **privileged execution**.

### 1. Page-Cache Corruption via AF_ALG Splice Race

The kernel's `AF_ALG` (crypto) subsystem exposes a socket-based interface for userspace cryptographic operations. The exploit abuses a race condition in how the kernel handles `splice()` from a file into an AF_ALG socket:

1. Open the target binary (e.g. `/usr/sbin/ipset`) **read-only**.
2. Create an AF_ALG AEAD socket bound to `authencesn(hmac(sha256),cbc(aes))`.
3. Send a small payload chunk through the AF_ALG socket with `MSG_MORE`, telling the kernel to expect more data.
4. `splice()` the target file's contents from an fd → pipe → AF_ALG socket.
5. Due to the CoW bug, the kernel **writes the attacker's payload bytes into the target file's page-cache pages** instead of properly isolating them.

The exploit repeats this for each 4-byte window until the entire target binary's cached pages are overwritten with a custom payload.

No write permission to the file is needed. The file on disk is unchanged — only the in-memory page cache is corrupted.

### 2. Cross-Container Propagation via Image Layer Sharing

Container runtimes (containerd, CRI-O) use overlay filesystems. When two containers share the same image layer, the kernel serves their file reads from the **same page-cache pages**.

This PoC image is built `FROM registry.k8s.io/kube-proxy:v1.35.2`. The kube-proxy DaemonSet on every Kubernetes node uses the exact same base layer. As a result, `/usr/sbin/ipset` in both containers maps to the **identical set of page-cache pages**.

When the unprivileged PoC container corrupts ipset's page cache, the corruption is immediately visible to the privileged kube-proxy container on the same node — with zero cross-container communication.

### 3. Privileged Execution by kube-proxy

kube-proxy runs as a **privileged** DaemonSet with `hostNetwork: true`. It periodically invokes `/usr/sbin/ipset` to manage iptables/ipset rules. When it next executes ipset, the kernel loads the corrupted page-cache pages, executing the attacker's payload with kube-proxy's full privileges:

- Full root on the node
- All capabilities
- Access to host namespaces

The payload in this PoC (`payload/payload.c`) simply mounts the host root filesystem and writes a marker file to `/root/res` as proof of node-level code execution.

### Attack Flow Diagram

```
┌──────────────────────────┐     ┌──────────────────────────┐
│   PoC Container          │     │   kube-proxy Container   │
│   (unprivileged)         │     │   (privileged)           │
│                          │     │                          │
│  1. Open /usr/sbin/ipset │     │                          │
│     (read-only)          │     │                          │
│                          │     │                          │
│  2. AF_ALG splice race   │     │                          │
│     corrupts page cache  │     │                          │
│          │               │     │                          │
└──────────┼───────────────┘     └──────────────────────────┘
           │                                  │
           ▼                                  │
  ┌─────────────────────┐                     │
  │  Kernel Page Cache   │                     │
  │  /usr/sbin/ipset     │◄────────────────────┘
  │  (CORRUPTED)         │     3. kube-proxy executes ipset
  │  contains attacker's │        → loads corrupted pages
  │  payload bytes       │        → payload runs as root
  └─────────────────────┘           on the host
```

## Repository Structure

```
.
├── cmd/copyfail/main.go          # Entry point; embeds compiled payload
├── internal/
│   ├── exploit/
│   │   ├── exploit.go            # Core exploit: AF_ALG splice race loop
│   │   └── patch.go              # Splits payload into 4-byte patch windows
│   └── alg/
│       └── alg.go                # AF_ALG AEAD socket abstraction
├── payload/
│   ├── payload.c                 # Validation payload (mount host fs, write marker)
│   └── nolibc/                   # Kernel's tiny libc for static, no-dependency payloads
├── deploy/
│   └── poc.yaml                  # Kubernetes Deployment manifest
├── Dockerfile                    # Built FROM kube-proxy to share image layers
├── Makefile                      # Build orchestration
└── docs/                         # Validation evidence from ACK (Alibaba Cloud)
```

## Prerequisites

- Go 1.25+
- A cross-compiler for the nolibc payload (default: `x86_64-linux-gnu-gcc`)
- Docker / Buildx
- A Kubernetes cluster running kube-proxy as a DaemonSet with `imagePullPolicy: IfNotPresent` (the default)
- Linux kernel **before** the CVE-2026-31431 fix

## Building

```bash
# Build payload + Go binary
make build

# Build Docker image
make docker-build

# Build and push to GHCR
make docker-push IMAGE=ghcr.io/<you>/copy-fail-poc TAG=latest
```

For `arm64` targets:

```bash
make build CC=aarch64-linux-gnu-gcc GOARCH=arm64
```

## Usage

### Deploy the PoC

```bash
kubectl apply -f deploy/poc.yaml
```

The Deployment creates a single unprivileged pod. It:

1. Runs `/bin/copyfail -target /usr/sbin/ipset` to corrupt the page cache.
2. Sleeps indefinitely so the pod stays running for observation.

### Verify the Escape

After kube-proxy next executes ipset (this typically happens within seconds due to its reconciliation loop, or on its next restart), check the **node**:

```bash
# SSH into the node, or use a privileged debug pod
cat /root/res
# Expected output: [*] success
```

The presence of `/root/res` on the host filesystem proves that attacker-supplied code executed with node-level privileges — written from inside kube-proxy's privileged container context.

### Clean Up

```bash
kubectl delete -f deploy/poc.yaml

# On the affected node(s), remove the marker and restart kube-proxy:
rm -f /root/res
systemctl restart kubelet   # or delete the kube-proxy pod to force re-pull
```

## Why kube-proxy + ipset?

kube-proxy is an ideal target because it is:

1. **Present on every node** — runs as a DaemonSet.
2. **Highly privileged** — `privileged: true`, `hostNetwork: true`.
3. **Ships ipset in its image** — ipset is a setuid binary used for iptables management.
4. **Uses `imagePullPolicy: IfNotPresent`** — once the attacker's image is pulled and shares the same base layer, the overlay lower-dir pages are shared.

Any privileged DaemonSet whose image contains a predictable binary could be targeted the same way.

## Customizing the Payload

The default payload (`payload/payload.c`) is a validation-only program that writes a marker file. To build a custom payload:

1. Edit `payload/payload.c`. The program is built against `nolibc` (the kernel's minimal C library) for a static, dependency-free binary.
2. Run `make payload` to cross-compile.
3. The compiled payload is embedded into the Go binary via `//go:embed`.

## Affected Versions

- **Linux kernel**: All versions before the CVE-2026-31431 patch.
- **Kubernetes**: Any version using an unpatched node kernel. The vulnerability is in the kernel, not in Kubernetes itself. Kubernetes merely provides the execution context (shared image layers + privileged DaemonSets) that elevates the impact from local page-cache corruption to full container escape.

## Mitigation

- **Patch the kernel.** This is the definitive fix.
- **Enable image layer isolation.** Some runtimes support per-container filesystem snapshots that prevent page-cache sharing.
- **Use read-only root filesystems** for kube-proxy (does not fully mitigate, but limits payload capabilities).
- **Restrict pod scheduling** to prevent untrusted workloads from landing on nodes running privileged DaemonSets with shared base images.

## Credits

- **CVE-2026-31431 discovery and disclosure**: [Theori / Xint](https://copy.fail/)
- **Cross-platform C payload**: [Tony Gies](https://github.com/tgies/copy-fail-c) (LGPL-2.1-or-later OR MIT)
- **nolibc**: Linux kernel selftests (`tools/include/nolibc/`)

## License

The Go exploit code in this repository is provided as-is for research purposes.

The payload (`payload/payload.c`) is derived from [copy-fail-c](https://github.com/tgies/copy-fail-c) and is dual-licensed under **LGPL-2.1-or-later** OR **MIT**. See [LICENSE-LGPL](LICENSE-LGPL) and [LICENSE-MIT](LICENSE-MIT).
