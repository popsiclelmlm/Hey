//go:build with_utls && with_clash_api && with_gvisor

package main

// 用真实 sing-box v1.11.0 校验 SingboxConfig.ets 生成器产出的配置 schema。
//
// SingboxConfig.ets 在 ArkTS 里没法直接跑，这里把它对各代表性节点会生成的 JSON
// 手工镜像出来（严格按生成器逻辑），喂给 libbox.NewService 解析+构建。NewService
// 不 Start，所以不需要真 tun/网络——能过就证明字段名/嵌套/协议结构对得上 sing-box。
//
// build 约束钉死与产物一致的 tags：缺 with_utls/with_clash_api 时 NewService 必失败，
// 这正是本测试当初抓出的构建漏洞。在本机跑：
//   cd libsingbox && go test -tags "with_gvisor with_utls with_clash_api" -run TestGeneratedConfigs -v

import (
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

func validateConfig(t *testing.T, name string, cfg string) {
	t.Helper()
	svc, err := libbox.NewService(cfg, newPlatformInterface())
	if err != nil {
		t.Errorf("[%s] sing-box 拒绝了配置: %v", name, err)
		return
	}
	_ = svc.Close()
	t.Logf("[%s] OK — sing-box 接受", name)
}

func TestGeneratedConfigs(t *testing.T) {
	tmp := t.TempDir()
	if err := libbox.Setup(&libbox.SetupOptions{BasePath: tmp, WorkingPath: tmp, TempPath: tmp}); err != nil {
		t.Fatalf("libbox.Setup: %v", err)
	}
	validateConfig(t, "vless-reality-tcp", vlessRealityTcp)
	validateConfig(t, "vmess-ws-tls", vmessWsTls)
	validateConfig(t, "trojan-grpc-tls", trojanGrpcTls)
	validateConfig(t, "shadowsocks", shadowsocksPlain)
}

// 以下 4 个常量严格对应 buildSingboxConfig() 在默认 settings 下的输出
// （remoteDns 1.1.1.1 / directDns 223.5.5.5 / mtu 1500 / ipv4_only / 10.10.14.1）。

const vlessRealityTcp = `{
 "log":{"level":"warn","timestamp":true},
 "dns":{"servers":[{"tag":"proxy-dns","address":"1.1.1.1","detour":"proxy"},{"tag":"direct-dns","address":"223.5.5.5","detour":"direct"}],"final":"proxy-dns","strategy":"ipv4_only"},
 "inbounds":[{"type":"tun","tag":"tun-in","interface_name":"vpn-tun","mtu":1500,"inet4_address":"10.10.14.1/30","auto_route":false,"stack":"gvisor","sniff":true,"sniff_override_destination":false}],
 "outbounds":[
   {"type":"vless","tag":"proxy","server":"1.2.3.4","server_port":443,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","packet_encoding":"xudp","flow":"xtls-rprx-vision","tls":{"enabled":true,"server_name":"a.example.com","utls":{"enabled":true,"fingerprint":"chrome"},"reality":{"enabled":true,"public_key":"jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0","short_id":"0123abcd"}}},
   {"type":"direct","tag":"direct"},
   {"type":"dns","tag":"dns-out"}
 ],
 "route":{"rules":[{"protocol":"dns","outbound":"dns-out"},{"ip_is_private":true,"outbound":"direct"}],"final":"proxy","auto_detect_interface":false}
}`

const vmessWsTls = `{
 "log":{"level":"warn","timestamp":true},
 "dns":{"servers":[{"tag":"proxy-dns","address":"1.1.1.1","detour":"proxy"},{"tag":"direct-dns","address":"223.5.5.5","detour":"direct"}],"final":"proxy-dns","strategy":"ipv4_only"},
 "inbounds":[{"type":"tun","tag":"tun-in","interface_name":"vpn-tun","mtu":1500,"inet4_address":"10.10.14.1/30","auto_route":false,"stack":"gvisor","sniff":true,"sniff_override_destination":false}],
 "outbounds":[
   {"type":"vmess","tag":"proxy","server":"5.6.7.8","server_port":443,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","security":"auto","alter_id":0,"tls":{"enabled":true,"server_name":"b.example.com","utls":{"enabled":true,"fingerprint":"chrome"}},"transport":{"type":"ws","path":"/wspath","headers":{"Host":"b.example.com"}}},
   {"type":"direct","tag":"direct"},
   {"type":"dns","tag":"dns-out"}
 ],
 "route":{"rules":[{"protocol":"dns","outbound":"dns-out"},{"ip_is_private":true,"outbound":"direct"}],"final":"proxy","auto_detect_interface":false}
}`

const trojanGrpcTls = `{
 "log":{"level":"warn","timestamp":true},
 "dns":{"servers":[{"tag":"proxy-dns","address":"1.1.1.1","detour":"proxy"},{"tag":"direct-dns","address":"223.5.5.5","detour":"direct"}],"final":"proxy-dns","strategy":"ipv4_only"},
 "inbounds":[{"type":"tun","tag":"tun-in","interface_name":"vpn-tun","mtu":1500,"inet4_address":"10.10.14.1/30","auto_route":false,"stack":"gvisor","sniff":true,"sniff_override_destination":false}],
 "outbounds":[
   {"type":"trojan","tag":"proxy","server":"9.10.11.12","server_port":443,"password":"trojan-pass","tls":{"enabled":true,"server_name":"c.example.com"},"transport":{"type":"grpc","service_name":"grpcsvc"}},
   {"type":"direct","tag":"direct"},
   {"type":"dns","tag":"dns-out"}
 ],
 "route":{"rules":[{"protocol":"dns","outbound":"dns-out"},{"ip_is_private":true,"outbound":"direct"}],"final":"proxy","auto_detect_interface":false}
}`

const shadowsocksPlain = `{
 "log":{"level":"warn","timestamp":true},
 "dns":{"servers":[{"tag":"proxy-dns","address":"1.1.1.1","detour":"proxy"},{"tag":"direct-dns","address":"223.5.5.5","detour":"direct"}],"final":"proxy-dns","strategy":"ipv4_only"},
 "inbounds":[{"type":"tun","tag":"tun-in","interface_name":"vpn-tun","mtu":1500,"inet4_address":"10.10.14.1/30","auto_route":false,"stack":"gvisor","sniff":true,"sniff_override_destination":false}],
 "outbounds":[
   {"type":"shadowsocks","tag":"proxy","server":"13.14.15.16","server_port":8388,"method":"aes-256-gcm","password":"ss-pass"},
   {"type":"direct","tag":"direct"},
   {"type":"dns","tag":"dns-out"}
 ],
 "route":{"rules":[{"protocol":"dns","outbound":"dns-out"},{"ip_is_private":true,"outbound":"direct"}],"final":"proxy","auto_detect_interface":false}
}`
