package main

/*
#include <stdint.h>
*/
import "C"

import (
	"fmt"
	"sync/atomic"

	"github.com/xjasonlyu/tun2socks/v2/engine"
	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

var running atomic.Bool

//export HeyTun2SocksStart
func HeyTun2SocksStart(tunFd C.int, socksHost *C.char, socksPort C.int, mtu C.int) C.int {
	if running.Load() {
		return 0
	}

	host := C.GoString(socksHost)
	if int(tunFd) < 0 || host == "" || int(socksPort) <= 0 || int(mtu) <= 0 {
		return -1
	}

	engine.Insert(&engine.Key{
		MTU:      int(mtu),
		Device:   fmt.Sprintf("fd://%d", int(tunFd)),
		Proxy:    fmt.Sprintf("socks5://%s:%d", host, int(socksPort)),
		LogLevel: "warn",
	})
	engine.Start()
	running.Store(true)
	return 0
}

//export HeyTun2SocksStop
func HeyTun2SocksStop() {
	if running.Swap(false) {
		engine.Stop()
	}
}

//export HeyTun2SocksUploadBytes
func HeyTun2SocksUploadBytes() C.int64_t {
	return C.int64_t(statistic.DefaultManager.Snapshot().UploadTotal)
}

//export HeyTun2SocksDownloadBytes
func HeyTun2SocksDownloadBytes() C.int64_t {
	return C.int64_t(statistic.DefaultManager.Snapshot().DownloadTotal)
}

func main() {}
