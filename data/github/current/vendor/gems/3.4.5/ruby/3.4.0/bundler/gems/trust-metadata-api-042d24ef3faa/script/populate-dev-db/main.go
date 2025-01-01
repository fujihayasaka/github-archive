package main

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/testing/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"golang.org/x/exp/rand"
	"google.golang.org/protobuf/encoding/protojson"
)

func main() {
	// Create client for filling the dev database
	tmaSvc, _ := service.NewTMAWithLocalDockerStorage(&testing.T{})
	bundles := [][]byte{
		data.SigstoreBundleMultipleSubjects,
		data.AttestDemoBigSBOM,
		data.AttestDemoBundleProvenance,
		data.AttestDemoBundleSBOM,
	}
	fetchInfo := make([]recordFetchInfo, len(bundles))
	for i, b := range bundles {
		fi := createAttestation(tmaSvc, b)
		fetchInfo[i] = fi
	}

	for _, fi := range fetchInfo {
		fmt.Println(fi.String())
	}
}

type recordFetchInfo struct {
	OwnerID       uint64                `json:"ownerId"`
	RepositoryID  uint64                `json:"repositoryId"`
	Subjects      []attestation.Subject `json:"subjects"`
	PredicateType string                `json:"predicateType"`
}

func (info *recordFetchInfo) String() string {
	b, err := json.Marshal(info)
	if err != nil {
		panic(err)
	}
	return string(b)
}

func createAttestation(svc *service.TMA, raw []byte) recordFetchInfo {
	var bundle protobundle.Bundle
	err := protojson.Unmarshal(raw, &bundle)
	if err != nil {
		panic(err)
	}
	//nolint:gosec
	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	ids := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	record, err := svc.CreateAttestation(context.Background(), &bundle, ids)
	if err != nil {
		panic(err)
	}

	return recordFetchInfo{
		OwnerID:       ownerID,
		RepositoryID:  repoID,
		Subjects:      record.Subjects,
		PredicateType: record.PredicateType,
	}
}
