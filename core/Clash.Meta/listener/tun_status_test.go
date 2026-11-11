package listener

import "testing"

func TestTunStatusDoesNotTrustRequestedConfiguration(t *testing.T) {
	if tunLister != nil {
		t.Fatal("test requires no live TUN listener")
	}
	previousConfig, previousError := LastTunConf, tunStartError
	t.Cleanup(func() { LastTunConf, tunStartError = previousConfig, previousError })
	LastTunConf.Enable = true
	LastTunConf.Device = "requested-only"
	tunStartError = "test startup failure"
	enabled, device, startError := TunStatus()
	if enabled || device != "" || startError != "test startup failure" {
		t.Fatalf("absent listener reported as live: %v, %q, %q", enabled, device, startError)
	}
}

func TestDisabledTunClearsPreviousStartupError(t *testing.T) {
	if tunLister != nil {
		t.Fatal("test requires no live TUN listener")
	}
	previousConfig, previousError := LastTunConf, tunStartError
	t.Cleanup(func() { LastTunConf, tunStartError = previousConfig, previousError })
	tunStartError = "test startup failure"
	config := LastTunConf
	config.Enable = false
	ReCreateTun(config, nil)
	enabled, device, startError := TunStatus()
	if enabled || device != "" || startError != "" {
		t.Fatalf("disabled listener has stale state: %v, %q, %q", enabled, device, startError)
	}
}
