package handlers

// import (
// 	"context"
// 	"encoding/json"
// 	"fmt"
// 	"testing"

// 	"github.com/github/billing-platform/lib/interfaces"
// 	"github.com/github/billing-platform/lib/models"
// 	"github.com/github/billing-platform/testing/stubs"
// 	"github.com/github/github-telemetry-go/log"
// 	"github.com/github/github-telemetry-go/telemetry"
// 	"github.com/onsi/gomega"
// )

// type InMemoryDB struct {
// 	Records []*models.ItemKey
// }

// func (db *InMemoryDB) UpsertWithOptions(ctx context.Context, _ log.Logger, item models.ItemKey, options *interfaces.QueryOptions) error {
// 	db.Records = append(db.Records, &item)
// 	return nil
// }

// func Test_RepositoryVisibilityChangedHandler_Updates_Repo_Metadata(t *testing.T) {
// 	telem, _ := telemetry.NewFromEnv()

// 	g := gomega.NewGomegaWithT(t)
// 	fakeDB := &InMemoryDB{
// 		Records: make([]*models.ItemKey, 0),
// 	}
// 	handler := RepositoryVisibilityChangedHandler{
// 		// DB: fakeDB,
// 	}

// 	repoId := stubs.GetRandomId64()
// 	isPublic := false

// 	envelope, err := stubs.CreateEnvelopeForVisibilityChangedEvent(repoId, isPublic)
// 	g.Expect(err).ToNot(gomega.HaveOccurred())

// 	err = handler.HandleEnvelope(context.Background(), telem.Logger, envelope)
// 	g.Expect(err).ToNot(gomega.HaveOccurred())

// 	jsonRecord, err := json.Marshal(fakeDB.Records[0])
// 	g.Expect(err).ToNot(gomega.HaveOccurred())
// 	g.Expect(string(jsonRecord)).Should(gomega.Equal(
// 		fmt.Sprintf("{\"partitionKey\":\"repos\",\"id\":\"%d\",\"RepoId\":%d,\"IsPublic\":%t}", repoId, repoId, isPublic),
// 	))

// 	isPublic = true

// 	envelope, err = stubs.CreateEnvelopeForVisibilityChangedEvent(repoId, isPublic)
// 	g.Expect(err).ToNot(gomega.HaveOccurred())

// 	err = handler.HandleEnvelope(context.Background(), telem.Logger, envelope)
// 	g.Expect(err).ToNot(gomega.HaveOccurred())

// 	jsonRecord, err = json.Marshal(fakeDB.Records[1])
// 	g.Expect(err).ToNot(gomega.HaveOccurred())
// 	g.Expect(string(jsonRecord)).Should(gomega.Equal(
// 		fmt.Sprintf("{\"partitionKey\":\"repos\",\"id\":\"%d\",\"RepoId\":%d,\"IsPublic\":%t}", repoId, repoId, isPublic),
// 	))
// }
