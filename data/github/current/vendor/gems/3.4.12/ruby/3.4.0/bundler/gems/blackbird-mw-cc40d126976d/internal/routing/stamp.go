package routing

type Stamp string

const (
	Dotcom      Stamp = "dotcom"
	StaffWUS201 Stamp = "staff-wus2-01"
	ProdWEU01   Stamp = "prod-weu-01"
	ProdSDC01   Stamp = "prod-sdc-01"
	ProdAE01    Stamp = "prod-ae-01"
)

var AllStamps = append([]Stamp{Dotcom}, ProximaStamps...)
var ProximaStamps = []Stamp{StaffWUS201, ProdWEU01, ProdSDC01, ProdAE01}

var ProximaCorpora = []Corpus{Blue, Green}

func (s Stamp) EnabledCorpora() []Corpus {
	switch s {
	case Dotcom:
		return Corpora
	default:
		return ProximaCorpora
	}
}

func (s Stamp) DeployEnv() string {
	if s == Dotcom {
		return "production"
	}
	return string(s)
}
