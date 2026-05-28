# Copy Fail (CVE-2026-31431) - Kubernetes Container Escape PoC
This project aims at demonstrating how the Copy Fail vulnerability (CVE-2026-31431) can be exploited on an Azure Kubernetes Service on Microsoft Azure if the proper countermeasures are ignored and/or disabled. Then, it shows how a forensic investigator can try to detect the attack occurrence relying on the native logs provided by the Azure platform and by using the logs provided by an eBPF-based monitoring tool like [Tetragon](https://tetragon.io).

Further details on the work can be found in the project [report](report.pdf) and [slides](presentation.pdf).

This project was developed during the 2026 edition of the Computer Forensics and Cyber Crime Analysis course in the Cybersecurity Master's degree at Politecnico di Torino.

> **Disclaimer:** This repository is published for educational and defensive purposes only. Use it exclusively on systems you own or have explicit authorization to test.

## Credits

- **CVE-2026-31431 discovery and disclosure**: [Theori / Xint](https://copy.fail/)
- **Cross-platform C payload**: [Tony Gies](https://github.com/tgies/copy-fail-c) (LGPL-2.1-or-later OR MIT)
- **nolibc**: Linux kernel selftests (`tools/include/nolibc/`)
- **Vulnerability Exploit on K8s PoC**: [Copy-Fail (CVE-2026-31431) Kubernetes-PoC](https://github.com/Percivalll/Copy-Fail-CVE-2026-31431-Kubernetes-PoC)


## License

The Go exploit code in this repository is provided as-is for research purposes.

The payload (`payload/payload.c`) is derived from [copy-fail-c](https://github.com/tgies/copy-fail-c) and is dual-licensed under **LGPL-2.1-or-later** OR **MIT**. See [LICENSE-LGPL](LICENSE-LGPL) and [LICENSE-MIT](LICENSE-MIT).
