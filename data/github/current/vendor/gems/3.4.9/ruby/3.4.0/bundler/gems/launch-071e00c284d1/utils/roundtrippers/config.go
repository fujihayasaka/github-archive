package roundtrippers

type RoundTripperConfig struct {
	TelemetryRoundTripperEnableLogs bool `config:"false,env=TELEMETRY_ROUND_TRIPPER_ENABLE_LOGS"`
}
