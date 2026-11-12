package ecosystems

import (
	"encoding/json"
	"fmt"

	"github.com/package-url/packageurl-go"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

// The package ecosystem (not language!) where package manager tools fetch dependencies from.
type Ecosystem uint

const (
	Unknown Ecosystem = iota
	NPM
	Maven
	Gradle
	Golang
	Nuget
	PyPi
	// add next ecosystem enum const here
)

const (
	ecoUnknownStr = "unknown"
	ecoNPMStr     = "npm"
	ecoMavenStr   = "maven"
	ecoGradleStr  = "gradle"
	ecoGolangStr  = "golang"
	ecoNugetStr   = "nuget"
	ecoPyPiStr    = "pypi"

	// add next ecosystem string rep here
)

func FromString(eco string) (Ecosystem, error) {
	switch eco {
	case ecoNPMStr:
		return NPM, nil

	case ecoMavenStr:
		return Maven, nil

	case ecoGradleStr:
		return Gradle, nil

	case ecoGolangStr:
		return Golang, nil

	case ecoNugetStr:
		return Nuget, nil

	case ecoPyPiStr:
		return PyPi, nil

	default:
		return Unknown, fmt.Errorf("unsupported ecosystem: %s", eco)
	}
}

// FromPurlType returns the ecosystem for a given Package URL type.
func FromPurlType(purlType string) (Ecosystem, error) {
	switch purlType {
	case packageurl.TypeNPM:
		return NPM, nil

	case packageurl.TypeMaven:
		return Maven, nil

	case packageurl.TypeGradle:
		return Gradle, nil

	case packageurl.TypeGolang:
		return Golang, nil

	case packageurl.TypeNuget:
		return Nuget, nil

	case packageurl.TypePyPi:
		return PyPi, nil

	default:
		return Unknown, fmt.Errorf("unsupported purl type: %s", purlType)
	}
}

func (e Ecosystem) String() string {
	switch e {
	case NPM:
		return ecoNPMStr

	case Maven:
		return ecoMavenStr

	case Gradle:
		return ecoGradleStr

	case Golang:
		return ecoGolangStr

	case Nuget:
		return ecoNugetStr

	case PyPi:
		return ecoPyPiStr

	// case NextEcosystemSupported: ...

	default:
	}

	return ecoUnknownStr
}

func (e Ecosystem) Humanize() string {
	switch e {
	case NPM:
		return "NPM"
	case PyPi:
		return "PyPi"
	default:
		caser := cases.Title(language.Und)
		return caser.String(e.String())
	}
}

func (e *Ecosystem) MarshalJSON() ([]byte, error) {
	return json.Marshal(e.String())
}

func (e Ecosystem) PurlType() string {
	switch e {
	case NPM:
		return packageurl.TypeNPM
	case Maven:
		return packageurl.TypeMaven
	case Gradle:
		return packageurl.TypeGradle
	case Golang:
		return packageurl.TypeGolang
	case Nuget:
		return packageurl.TypeNuget
	case PyPi:
		return packageurl.TypePyPi
	}
	panic(fmt.Sprintf("no purl type for ecosystem %s", e.String()))
}
