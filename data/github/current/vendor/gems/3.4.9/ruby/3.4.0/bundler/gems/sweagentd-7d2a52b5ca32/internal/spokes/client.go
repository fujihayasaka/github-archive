package spokes

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/transactions"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/twitchtv/twirp"
)

var (
	// ErrNotFound is returned when a requested resource is not found.
	ErrNotFound = errors.New("not found")

	// ErrDefaultBranchNotFound is returned when the default branch cannot be found.
	ErrDefaultBranchNotFound = errors.New("default branch not found")

	// objectIDRegex matches a valid Git object ID (SHA-1 or SHA-256)
	objectIDRegex = regexp.MustCompile(`^[a-fA-F0-9]{40}$|^[a-fA-F0-9]{64}$`)
)

// Client is a client for interacting with the Spokes API.
type Client struct {
	obsv               observability.Exporters
	blobClient         blobs.BlobsAPI
	treesClient        trees.TreesAPI
	objectsClient      objects.ObjectsAPI
	referencesClient   references.ReferencesAPI
	transactionsClient transactions.TransactionsAPI
}

// NewClient creates a new Spokes client with the given HMAC key.
func NewClient(obsv observability.Exporters, addr, cert, key, caChain string) (*Client, error) {
	c, err := newTwirpClient(cert, key, caChain)
	if err != nil {
		return nil, err
	}

	hooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			req.Header.Set("User-Agent", "sweagentd")

			if reqID := requestid.GetGitHubRequestID(ctx); reqID != "" {
				req.Header.Set(headers.GitHubRequestID, reqID)
			}

			return ctx, nil
		},
	}
	hooksOpt := twirp.WithClientHooks(hooks)

	blobClient := blobs.NewBlobsAPIProtobufClient(addr, c, hooksOpt)
	treesClient := trees.NewTreesAPIProtobufClient(addr, c, hooksOpt)
	objectsClient := objects.NewObjectsAPIProtobufClient(addr, c, hooksOpt)
	referencesClient := references.NewReferencesAPIProtobufClient(addr, c, hooksOpt)
	transactionsClient := transactions.NewTransactionsAPIProtobufClient(addr, c, hooksOpt)

	return &Client{
		obsv:               obsv,
		blobClient:         blobClient,
		treesClient:        treesClient,
		objectsClient:      objectsClient,
		referencesClient:   referencesClient,
		transactionsClient: transactionsClient,
	}, nil
}

// NewClientFromConfig creates a new Spokes client from the given configuration.
func NewClientFromConfig(obsv observability.Exporters, cfg *config.Config) (*Client, error) {
	return NewClient(obsv, cfg.SpokesURL, cfg.SpokesCert, cfg.SpokesKey, cfg.SpokesCA)
}

// ReadBlob reads the contents of the blob at the given path in the specified repository.
// If the blob does not exist, it returns ErrNotFound.
func (c *Client) ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "spokes.Client.ReadBlob")
	defer span.End()

	// Resolve the default branch to get the file using the branch's OID to avoid a race condition
	oid, err := c.getDefaultBranchOID(ctx, repoID)
	if err != nil {
		return nil, "", goerrors.Errorf("failed to get default branch SHA: %w", err)
	}
	contents, err := c.ReadBlobByObjectIDPath(ctx, repoID, oid, path)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			if twerr.Code() == twirp.NotFound {
				return nil, "", newNotFound()
			}
		}

		return nil, "", goerrors.Errorf("failed to get blob contents: %w", err)
	}

	return contents, oid, nil
}

// ReadBlobByObjectIDPath reads the contents of the blob at the given path in the specified repository.
// If the blob does not exist, it returns ErrNotFound.
func (c *Client) ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "spokes.Client.ReadBlobByObjectIDPath")
	defer span.End()

	req := blobs.NewGetBlobContentsRequestByObjectIDPath(
		types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
		types.NewRepository(repoID),
		types.NewObjectID(oid),
		types.NewPath([]byte(path)),
		nil,
	)

	resp, err := c.blobClient.GetBlobContents(ctx, req)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			if twerr.Code() == twirp.NotFound {
				return nil, newNotFound()
			}
		}

		return nil, goerrors.Errorf("failed to get blob contents: %w", err)
	}

	return resp.GetContents(), nil
}

// ListTrees lists the files under the given path in the specified repository.
// If no files exist under the path, it returns an empty list.
// If the path does not exist, it returns ErrNotFound.
func (c *Client) ListTrees(ctx context.Context, repoID uint64, path string) ([]*sweagentd.SpokesObject, string, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "spokes.Client.ListTrees")
	defer span.End()

	oid, err := c.getDefaultBranchOID(ctx, repoID)
	if err != nil {
		// An uninitialized repository will not have a default branch - so return empty list in this case
		if errors.Is(err, ErrDefaultBranchNotFound) {
			return []*sweagentd.SpokesObject{}, "", nil
		}
		return nil, "", goerrors.Errorf("failed to list trees: %w", err)
	}

	selector := selectors.NewTreeishAndPathSelector(
		types.NewTreeishWithObjectID(types.NewObjectID(oid)),
		types.NewPath([]byte(path)))

	req := trees.NewListTreesRequestWithTreeishAndPathSelector(
		types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
		types.NewRepository(repoID),
		selector)

	resp, err := c.treesClient.ListTrees(ctx, req)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			if twerr.Code() == twirp.NotFound {
				return nil, "", newNotFound()
			}
		}

		return nil, "", goerrors.Errorf("failed to list trees: %w", err)
	}

	entries := resp.GetEntries()
	objs := make([]*sweagentd.SpokesObject, len(entries))
	for i, entry := range entries {
		objs[i] = &sweagentd.SpokesObject{
			Oid:  entry.GetObject().GetOid().GetId(),
			Path: string(entry.GetPath().GetName()),
		}
	}

	return objs, oid, nil
}

// ReadBlobObjects reads multiple blob objects by their OIDs in a single request.
// It returns a slice of byte slices, each containing the contents of the corresponding blob.
// The order of the returned blobs matches the order of the provided OIDs.
func (c *Client) ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "spokes.Client.ReadBlobObjects")
	defer span.End()

	var sels []*selectors.ObjectSelector
	for _, oid := range oids {
		sels = append(sels, selectors.NewObjectSelectorByObjectID(types.NewObjectID(oid)))
	}

	req := objects.NewReadObjectsRequest(
		types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
		types.NewRepository(repoID),
		sels...,
	)

	resp, err := c.objectsClient.ReadObjects(ctx, req)
	if err != nil {
		return nil, err
	}

	bo := make([][]byte, 0, len(resp.GetObjects()))
	for _, obj := range resp.GetObjects() {
		bo = append(bo, obj.GetBlobObject().GetData())
	}

	return bo, nil
}

// CreateEmptyBranch creates a new branch with an empty commit in the specified repository.
// It creates a branch from the base branch, then creates an empty commit with the same tree.
// The committer name and email are used for both the commit author and committer.
func (c *Client) CreateEmptyBranch(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "spokes.Client.CreateEmptyBranch")
	defer span.End()

	tran, err := c.transactionsClient.BeginTransaction(ctx, &transactions.BeginTransactionRequest{
		Repository:     types.NewRepository(opts.RepoID),
		RequestContext: types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
	})
	if err != nil {
		return "", goerrors.Errorf("failed to begin transaction: %w", err)
	}

	// Resolve the base branch to get its OID
	committerName := opts.CommitterName
	committerEmail := opts.CommitterEmail

	// If the base ref is a full ref (e.g., refs/heads/main) or branch name (e.g., main), resolve it to an OID
	baseCommitOID, err := c.committishToOID(ctx, opts.RepoID, opts.BaseRef)
	if err != nil {
		return "", goerrors.Errorf("failed to determine base ref OID: %w", err)
	}

	// Read the base commit to get its tree OID
	readReq := objects.NewReadObjectsRequest(
		types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
		types.NewRepository(opts.RepoID),
		selectors.NewObjectSelectorByObjectID(types.NewObjectID(baseCommitOID)),
	)
	readResp, err := c.objectsClient.ReadObjects(ctx, readReq)
	if err != nil {
		return "", goerrors.Errorf("failed to read base commit: %w", err)
	}
	if len(readResp.GetObjects()) == 0 {
		return "", goerrors.New("base commit not found")
	}
	baseCommit := readResp.GetObjects()[0].GetCommitObject()
	if baseCommit == nil {
		return "", goerrors.New("base object is not a commit")
	}
	treeOID := baseCommit.GetTreeOid().GetId()

	// Create a new commit object with the same tree (empty commit)
	// Git commit format: tree <sha>\nparent <sha>\nauthor <name> <email> <timestamp> <timezone>\ncommitter <name> <email> <timestamp> <timezone>\n\n<message>
	timestamp := fmt.Sprintf("%d +0000", time.Now().Unix())
	commitContent := fmt.Sprintf("tree %s\nparent %s\nauthor %s <%s> %s\ncommitter %s <%s> %s\n\nInitial plan\n",
		treeOID, baseCommitOID, committerName, committerEmail, timestamp, committerName, committerEmail, timestamp)

	createReq := &objects.CreateObjectsRequest{
		Repository: types.NewRepository(opts.RepoID),
		RequestContext: types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
			types.WithTransactionContext(tran.GetTransactionContext())),
		Objects: []*objects.CreatableObject{
			{
				Content: []byte(commitContent),
				Type:    &types.ObjectType{Type: types.Object_TYPE_COMMIT},
			},
		},
	}
	createResp, err := c.objectsClient.CreateObjects(ctx, createReq)
	if err != nil {
		return "", goerrors.Errorf("failed to create commit object: %w", err)
	}
	if len(createResp.GetOids()) == 0 {
		return "", goerrors.New("no commit OID returned")
	}
	newCommitOID := createResp.GetOids()[0].GetId()

	_, err = c.transactionsClient.CommitTransaction(ctx, &transactions.CommitTransactionRequest{
		Repository: types.NewRepository(opts.RepoID),
		RequestContext: types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY,
			types.WithTransactionContext(tran.GetTransactionContext()),
		),
	})
	if err != nil {
		return "", goerrors.Errorf("failed to commit transaction: %w", err)
	}

	// Create/update the branch reference to point to the new commit
	branchRef := fmt.Sprintf("refs/heads/%s", opts.BranchName)
	updateReq := &references.UpdateRequest{
		Repository: types.NewRepository(opts.RepoID),
		Priority:   &types.UpdateReferencesPriority{Priority: types.UpdateReferencesPriority_PRIORITY_HIGH},
		Txn: &references.Transaction{
			CommitterName:  []byte(committerName),
			CommitterEmail: []byte(committerEmail),
			CommitterTime:  timestamp,
			ReflogMsg:      "Create branch with empty commit",
			RefUpdate: []*references.UpdateRefRequest{
				{
					FastForward: references.UpdateRefRequest_FAST_FORWARD_FALSE,
					Reference:   types.NewReference([]byte(branchRef)),
					Operation: &references.UpdateRefRequest_RefUpdate{
						RefUpdate: &references.UpdateRefOpUpdate{
							Oid: types.NewObjectID(newCommitOID),
						},
					},
				},
			},
		},
	}
	_, err = c.referencesClient.Update(ctx, updateReq)
	if err != nil {
		return "", goerrors.Errorf("failed to create/update branch reference: %w", err)
	}

	return newCommitOID, nil
}

// Resolve the default branch to get the file using the branch's OID to avoid a race condition
func (c *Client) getDefaultBranchOID(ctx context.Context, repoID uint64) (string, error) {
	oids, err := c.resolveReferences(ctx, repoID, []string{string(types.DefaultBranch().Name)})
	if err != nil {
		return "", goerrors.Errorf("failed to resolve reference: %w", err)
	}
	if len(oids) == 0 || oids[0] == "" {
		return "", newDefaultBranchNotFound()
	}

	return oids[0], nil
}

// committishToOID determines if the given ref is a branch name, tag name, or commit SHA.
func (c *Client) committishToOID(ctx context.Context, repoID uint64, ref string) (string, error) {
	if strings.HasPrefix(ref, "refs/heads/") {
		oids, err := c.resolveReferences(ctx, repoID, []string{ref})
		if err != nil {
			return "", goerrors.Errorf("failed to resolve base ref: %w", err)
		}
		if len(oids) == 0 || oids[0] == "" {
			return "", goerrors.New("base ref not found")
		}
		return oids[0], nil
	}

	if strings.HasPrefix(ref, "refs/tags/") {
		return "", goerrors.New("tag refs not supported")
	}

	if isValidObjectID(ref) {
		return ref, nil
	}

	// Assume branch name, it's just missing the refs/heads/ prefix
	return c.committishToOID(ctx, repoID, "refs/heads/"+ref)
}

// isValidObjectID checks if a string is a valid Git object ID (SHA-1 or SHA-256)
func isValidObjectID(id string) bool {
	return objectIDRegex.MatchString(id)
}

// ResolveReferences resolves the given references to their corresponding OIDs in the specified repository.
// It returns a slice of OIDs in the same order as the input references with an empty string for any reference that could not be resolved.
func (c *Client) resolveReferences(ctx context.Context, repoID uint64, refs []string) ([]string, error) {
	var resolvedRefs []*types.Reference
	for _, ref := range refs {
		resolvedRefs = append(resolvedRefs, types.NewReference([]byte(ref)))
	}
	resp, err := c.referencesClient.ResolveReferences(ctx, &references.ResolveReferencesRequest{
		RequestContext: types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY),
		Repository:     types.NewRepository(repoID),
		References:     resolvedRefs,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to resolve reference: %w", err)
	}

	var oids []string
	for _, ref := range resp.GetItems() {
		if ref == nil || ref.GetOid() == nil {
			oids = append(oids, "")
		} else {
			oids = append(oids, ref.GetOid().Id)
		}
	}
	return oids, nil
}

type httpClient interface {
	Do(req *http.Request) (*http.Response, error)
}

func newTwirpClient(cert, key, caChain string) (httpClient, error) {
	c := &http.Client{
		Timeout: 30 * time.Second,
	}
	if cert == "" && key == "" && caChain == "" {
		// No TLS config provided, return default client.
		return c, nil
	}

	tlscfg, err := newTLSConfig(cert, key, caChain)
	if err != nil {
		return nil, goerrors.Errorf("failed to create TLS config: %w", err)
	}

	c.Transport = &http.Transport{
		TLSClientConfig:   tlscfg,
		ForceAttemptHTTP2: true,
	}

	return c, nil
}

func newTLSConfig(cert, key, caChain string) (*tls.Config, error) {
	cfg := &tls.Config{
		MinVersion: tls.VersionTLS12,
	}

	if cert != "" && key != "" {
		cert, err := tls.X509KeyPair([]byte(cert), []byte(key))
		if err != nil {
			return nil, goerrors.Errorf("failed to load client certificate: %w", err)
		}

		cfg.Certificates = []tls.Certificate{cert}
	}

	if caChain != "" {
		// Set up a cert pool that includes spokesd's CA.
		caPool, err := x509.SystemCertPool()
		if err != nil {
			return nil, goerrors.Errorf("failed to load system cert pool: %w", err)
		}

		if !caPool.AppendCertsFromPEM([]byte(caChain)) {
			return nil, goerrors.New("failed to append spokesd CA to cert pool")
		}

		cfg.RootCAs = caPool
	}

	return cfg, nil
}

func newNotFound() error {
	return goerrors.WithStackOffset(ErrNotFound, 1)
}

func newDefaultBranchNotFound() error {
	return goerrors.WithStackOffset(ErrDefaultBranchNotFound, 1)
}
