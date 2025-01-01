package ts

// ThreatModel represents whether the user has selected to include local and remote sources
// or only remote sources in their code scanning default setup analysis.
type ThreatModel uint8

const (
	ThreatModel_REMOTE ThreatModel = iota
	ThreatModel_REMOTE_LOCAL
)
