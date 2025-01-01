package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/test/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"golang.org/x/exp/rand"
	"google.golang.org/protobuf/encoding/protojson"
)

func main() {
	var useSingleOwner = flag.Bool("single-owner", false, "should the records be created with a single owner and repo ID")
	flag.Parse()
	// Create client for filling the dev database
	tmaSvc, _ := service.NewTMAWithLocalDockerStorage(&testing.T{})
	bundles := [][]byte{
		data.SigstoreBundleMultipleSubjects,
		data.AttestDemoBigSBOM,
		data.AttestDemoBundleProvenance,
		data.AttestDemoBundleSBOM,
	}

	var ownerID, repoID uint64
	if *useSingleOwner {
		//nolint:gosec
		ownerID, repoID = uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	}
	fetchInfo := make([]recordFetchInfo, len(bundles))
	for i, b := range bundles {
		fi := createAttestation(tmaSvc, b, ownerID, repoID)
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

func createAttestation(svc *service.TMA, raw []byte, ownerID, repoID uint64) recordFetchInfo {
	var bundle protobundle.Bundle
	if err := protojson.Unmarshal(raw, &bundle); err != nil {
		panic(err)
	}

	if ownerID == 0 && repoID == 0 {
		//nolint:gosec
		ownerID, repoID = uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	}
	ids := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
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
