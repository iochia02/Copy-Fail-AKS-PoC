FROM fedora:43 AS busybox
RUN dnf install -y busybox binutils gdb && dnf clean all

FROM mcr.microsoft.com/oss/v2/kubernetes/kube-proxy:v1.34.4-1 AS kube-proxy
COPY --from=busybox /bin/busybox.musl.static /bin/busybox

RUN ["/bin/busybox", "--install", "-s", "/bin"]
COPY bin/copyfail /bin/copyfail
COPY cmd/copyfail/payload /bin/payload
CMD ["/bin/copyfail"]