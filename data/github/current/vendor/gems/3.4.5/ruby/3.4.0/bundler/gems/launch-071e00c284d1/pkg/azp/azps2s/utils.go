package azps2s

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/launch/workflowbuild/azp/azptypes"
)

func intToBytes(i int) (*bytes.Buffer, error) {
	buf := new(bytes.Buffer)
	err := binary.Write(buf, binary.BigEndian, int64(i))
	return buf, err
}

func getRandomTenantName() (string, error) {
	// generate as long a random valid AZP identifer as possible (50 chars), by
	// generating a 50 char base62 string, replacing any '+' or '/'s.
	//
	// We end up with 297.71 bits of entropy

	desiredLength := 50
	bitsPerChar := 6

	// generate a base string, and a source of replacement chars for any '+' or '/'s
	random := make([]byte, desiredLength*bitsPerChar*2)
	_, err := rand.Read(random)
	if err != nil {
		return "", err
	}

	base64String := base64.StdEncoding.WithPadding(base64.NoPadding).EncodeToString(random)
	base62Output := strings.Builder{}

	for _, c := range base64String {
		if c == '/' || c == '+' {
			continue
		}
		base62Output.WriteRune(c)
		if base62Output.Len() == desiredLength {
			return base62Output.String(), nil
		}

	}

	// should have bought a lottery ticket...
	// TODO make this recurse instead
	return "", errors.New("could not generate org name")
}

func responseToResult(res *createOrganizationResponse) *azptypes.CreationResult {
	projectName := res.Project.Name
	if projectName == "" {
		projectName = AZPDefaultProjectName
	}

	pipelinesScaleUnitID := ""
	if val, ok := res.Organization.Properties[PipelineScaleUnitType]; ok {
		pipelinesScaleUnitID = val.Value
	}

	artifactCacheScaleUnitID := ""
	if val, ok := res.Organization.Properties[ArtifactCacheScaleUnitType]; ok {
		artifactCacheScaleUnitID = val.Value
	}

	runnerScaleUnitID := ""
	if val, ok := res.Organization.Properties[RunnerScaleUnitType]; ok {
		runnerScaleUnitID = val.Value
	}

	return &azptypes.CreationResult{
		TenantName:               res.Organization.Name,
		TenantID:                 res.Organization.ID,
		ProjectName:              projectName,
		PipelineID:               res.PipelineID,
		ClientID:                 res.Application.ClientID,
		PipelinesScaleUnitID:     pipelinesScaleUnitID,
		ArtifactCacheScaleUnitID: artifactCacheScaleUnitID,
		RunnerScaleUnitID:        runnerScaleUnitID,
	}
}
