//go:build integration
// +build integration

package integrationtests_test

import (
	"testing"

	"github.com/github/billing-platform/testing/integration"
	"github.com/github/billing-platform/testing/stubs"
	"github.com/onsi/gomega"
)

func Test_RepoMetaDataSync_HydroConsumer_Receives_Messages_And_ExecutesHandlers(t *testing.T) {
	client, g := integration.NewTestClient(t, integration.ClientOptions{})
	defer client.Close()

	repoId := stubs.GetRandomId64()

	err := client.CreateRepo(repoId, false)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	repo, err := client.GetRepo(repoId)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(repo.IsPublic).To(gomega.BeFalse())

	err = client.PublishRepoVisibilityChangedEvent(repoId, true)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	err = client.RunConsumer(1)
	g.Expect(err).ToNot(gomega.HaveOccurred())

	repo, err = client.GetRepo(repoId)
	g.Expect(err).ToNot(gomega.HaveOccurred())
	g.Expect(repo.IsPublic).To(gomega.BeTrue())
}
