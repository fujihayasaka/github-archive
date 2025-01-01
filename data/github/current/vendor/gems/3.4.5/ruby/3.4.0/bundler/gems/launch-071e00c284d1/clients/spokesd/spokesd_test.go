package spokesd

import (
	"archive/tar"
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/streaming"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type tarrableBlob struct {
	content []byte
	oid     string
}

func TestResolveObject(t *testing.T) {
	reqRef := "main"

	req := &objects.ResolveObjectRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		ObjectName: &types.Revision{
			Name: []byte(reqRef),
		},
	}

	resp := &objects.ResolveObjectResponse{
		Oid: &types.ObjectID{
			Id: "resolved-object-id",
		},
	}
	mockObjectsAPI := NewMockObjectsService(t)
	mockObjectsAPI.EXPECT().ResolveObject(mock.Anything, req).Return(resp, nil)
	s, _ := NewMockTestClient(nil, mockObjectsAPI, nil, "")

	res, err := s.ResolveObject(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, "resolved-object-id", res.Oid.Id)
}

func TestResolveObjectsByRef(t *testing.T) {
	reqRef1 := "refs/heads/main"
	reqRef2 := "refs/heads/test"

	req := &ResolveObjectsRequest{
		RepositoryID: 1,
		ActorID:      1,
		ObjectIdentifierList: []*ObjectIdentifier{
			{
				Ref: reqRef1,
			},
			{
				Ref: reqRef2,
			},
		},
		QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
	}

	resolveObjectsAPIRequest := &objects.ResolveObjectsRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		Selectors: []*selectors.ObjectSelector{
			{
				Object: &selectors.ObjectSelector_ByName{
					ByName: &types.Revision{
						Name: []byte(reqRef1),
					},
				},
			},
			{
				Object: &selectors.ObjectSelector_ByName{
					ByName: &types.Revision{
						Name: []byte(reqRef2),
					},
				},
			},
		},
	}
	resolveObjectsResponse := &objects.ResolveObjectsResponse{
		Items: []*objects.ResolveObjectsResponse_ResolvedItem{
			{
				Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
					Object: &types.Object{
						Type: types.Object_TYPE_COMMIT,
						Oid: &types.ObjectID{
							Id: "test-commit-id-1",
						},
					},
				},
			},
			{
				Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
					Object: &types.Object{
						Type: types.Object_TYPE_COMMIT,
						Oid: &types.ObjectID{
							Id: "test-commit-id-2",
						},
					},
				},
			},
		},
	}
	mockObjectsAPI := NewMockObjectsService(t)
	mockObjectsAPI.EXPECT().ResolveObjects(mock.Anything, resolveObjectsAPIRequest).Return(resolveObjectsResponse, nil)
	s, _ := NewMockTestClient(nil, mockObjectsAPI, nil, "")

	res, err := s.ResolveObjectsByRef(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, 2, len(res.Items))
	assert.Equal(t, "", res.Items[0].GetError())
	assert.Equal(t, "", res.Items[1].GetError())
	assert.Equal(t, "test-commit-id-1", res.Items[0].GetObject().Oid.Id)
	assert.Equal(t, "test-commit-id-2", res.Items[1].GetObject().Oid.Id)
}

func TestResolveObjectsByCommitSHAAndPath(t *testing.T) {
	reqPath1 := ".github/workflows/test-1.yml"
	reqPath2 := ".github/workflows/test-2.yml"
	reqSHA1 := "test-commit-id-1"
	reqSHA2 := "test-commit-id-2"

	req := &ResolveObjectsRequest{
		RepositoryID: 1,
		ActorID:      1,
		ObjectIdentifierList: []*ObjectIdentifier{
			{
				Path: reqPath1,
				SHA:  reqSHA1,
			},
			{
				Path: reqPath2,
				SHA:  reqSHA2,
			},
		},
		QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
	}

	resolveObjectsAPIRequest := &objects.ResolveObjectsRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		Selectors: []*selectors.ObjectSelector{
			{
				Object: &selectors.ObjectSelector_ByTreeishAndPath{
					ByTreeishAndPath: &selectors.ObjectSelector_TreeishAndPath{
						Treeish: &types.Treeish{
							Treeish: &types.Treeish_Oid{
								Oid: &types.ObjectID{
									Id: reqSHA1,
								},
							},
						},
						Path: &types.Path{
							Name: []byte(reqPath1),
						},
					},
				},
			},
			{
				Object: &selectors.ObjectSelector_ByTreeishAndPath{
					ByTreeishAndPath: &selectors.ObjectSelector_TreeishAndPath{
						Treeish: &types.Treeish{
							Treeish: &types.Treeish_Oid{
								Oid: &types.ObjectID{
									Id: reqSHA2,
								},
							},
						},
						Path: &types.Path{
							Name: []byte(reqPath2),
						},
					},
				},
			},
		},
	}
	resolveObjectsResponse := &objects.ResolveObjectsResponse{
		Items: []*objects.ResolveObjectsResponse_ResolvedItem{
			{
				Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
					Object: &types.Object{
						Type: types.Object_TYPE_BLOB,
						Oid: &types.ObjectID{
							Id: "test-object-id-1",
						},
					},
				},
			},
			{
				Item: &objects.ResolveObjectsResponse_ResolvedItem_Object{
					Object: &types.Object{
						Type: types.Object_TYPE_BLOB,
						Oid: &types.ObjectID{
							Id: "test-object-id-2",
						},
					},
				},
			},
		},
	}
	mockObjectsAPI := NewMockObjectsService(t)
	mockObjectsAPI.EXPECT().ResolveObjects(mock.Anything, resolveObjectsAPIRequest).Return(resolveObjectsResponse, nil)
	s, _ := NewMockTestClient(nil, mockObjectsAPI, nil, "")

	res, err := s.ResolveObjectsByCommitShaAndPath(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, 2, len(res.Items))
	assert.Equal(t, "", res.Items[0].GetError())
	assert.Equal(t, "", res.Items[1].GetError())
	assert.Equal(t, "test-object-id-1", res.Items[0].GetObject().Oid.Id)
	assert.Equal(t, "test-object-id-2", res.Items[1].GetObject().Oid.Id)
}

func TestCheckCommitReachability(t *testing.T) {
	req := &commits.CheckCommitReachabilityRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		Selector: &commits.CheckCommitReachabilityRequest_ObjectIdSelector{
			ObjectIdSelector: &selectors.ObjectIDSelector{
				Oids: []*types.ObjectID{
					{
						Id: "reachable-commit-id",
					},
					{
						Id: "unreachable-commit-id",
					},
				},
			},
		},
	}
	resp := &commits.CheckCommitReachabilityResponse{
		Commits: []*types.ObjectID{
			{
				Id: "reachable-commit-id",
			},
		},
	}
	mockCommitsAPI := NewMockCommitsService(t)
	mockCommitsAPI.EXPECT().CheckCommitReachability(mock.Anything, req).Return(resp, nil)
	s, _ := NewMockTestClient(nil, nil, mockCommitsAPI, "")

	res, err := s.CheckCommitReachability(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, 1, len(res.Commits))
	assert.Equal(t, "reachable-commit-id", res.Commits[0].Id)
}

func TestCheckCommitReachability_RequestHeaders(t *testing.T) {
	_, url, teardown := newRemoteServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/twirp/github.spokes.commits.v1.CommitsAPI/CheckCommitReachability", r.URL.Path)

		_, err := io.ReadAll(r.Body)
		defer r.Body.Close()

		require.NoError(t, err)

		require.Equal(t, "spokes-test/v1.0", r.Header.Get("User-Agent"))
		require.Equal(t, "20", r.Header.Get("Request-Timeout"))

		require.NoError(t, err)
	}))
	defer teardown()

	s, _ := NewMockTestClient(nil, nil, nil, url.String())

	req := commits.CheckCommitReachabilityRequest{
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
		},
	}
	resp, err := s.CheckCommitReachability(context.TODO(), &req)
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestGetBlobContentsBatch(t *testing.T) {
	expectedBlobs := []tarrableBlob{
		{oid: "object-id-1", content: []byte("abc")},
		{oid: "object-id-2", content: []byte("xyz")},
		{oid: "object-id-3", content: []byte("mno")},
	}

	_, url, teardown := newRemoteServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/streaming/v1/blobs", r.URL.Path)

		respBodyBytes, err := tarball(expectedBlobs)
		require.NoError(t, err)

		w.Header().Set("Content-Type", streaming.TarContentType)

		_, err = w.Write(respBodyBytes)
		require.NoError(t, err)
	}))
	defer teardown()

	s, _ := NewMockTestClient(nil, nil, nil, url.String())
	batchBlobsRequest := &GetBlobContentsBatchRequest{
		RepositoryID:     1,
		ActorID:          1,
		ObjectIDs:        []string{"object-id-1", "object-id-2"},
		QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
	}

	batchBlobContentsResp, err := s.GetBlobContentsBatch(context.TODO(), batchBlobsRequest)
	require.NoError(t, err)
	assert.NotNil(t, batchBlobContentsResp)
	assert.Equal(t, batchBlobsRequest.RepositoryID, batchBlobContentsResp.RepositoryID)
	assert.Equal(t, 3, len(batchBlobContentsResp.BlobContentsByID))
	assert.Equal(t, "abc", string(batchBlobContentsResp.BlobContentsByID["object-id-1"]))
	assert.Equal(t, "xyz", string(batchBlobContentsResp.BlobContentsByID["object-id-2"]))
	assert.Equal(t, "mno", string(batchBlobContentsResp.BlobContentsByID["object-id-3"]))
}

func TestGetBlobContentsById(t *testing.T) {
	req := &blobs.GetBlobContentsRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		Blob: &blobs.GetBlobContentsRequest_ById{
			ById: &types.ObjectID{
				Id: "blob-1",
			},
		},
	}
	resp := &blobs.GetBlobContentsResponse{
		Contents:  []byte("abc"),
		Truncated: false,
	}
	mockBlobsAPI := NewMockBlobsService(t)
	mockBlobsAPI.EXPECT().GetBlobContents(mock.Anything, req).Return(resp, nil)
	s, _ := NewMockTestClient(mockBlobsAPI, nil, nil, "")

	res, err := s.GetBlobContents(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, "abc", string(res.Contents))
}

func TestGetBlobContentsByRefPath(t *testing.T) {
	req := &blobs.GetBlobContentsRequest{
		Repository: &types.Repository{
			Type: types.Repository_TYPE_REPOSITORY,
			Id:   1,
		},
		RequestContext: &types.RequestContext{
			QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			UserId:           1,
		},
		Blob: &blobs.GetBlobContentsRequest_ByRefPath{
			ByRefPath: &blobs.GetBlobContentsRequest_RefPath{
				Reference: &types.Reference{
					Name: []byte("main"),
				},
				Path: &types.Path{
					Name: []byte("abc.yml"),
				},
			},
		},
	}
	resp := &blobs.GetBlobContentsResponse{
		Contents:  []byte("abc"),
		Truncated: false,
	}
	mockBlobsAPI := NewMockBlobsService(t)
	mockBlobsAPI.EXPECT().GetBlobContents(mock.Anything, req).Return(resp, nil)
	s, _ := NewMockTestClient(mockBlobsAPI, nil, nil, "")

	res, err := s.GetBlobContents(context.TODO(), req)
	require.NoError(t, err)
	assert.Equal(t, "abc", string(res.Contents))
}

// Sets up a remote server which will mock the http calls
func newRemoteServer(hdl http.Handler) (*httptest.Server, *url.URL, func()) {
	server := httptest.NewServer(hdl)
	urlProvider, err := url.Parse(server.URL)
	if err != nil {
		panic(err)
	}
	return server, urlProvider, server.Close
}

// tarball builds a tarball of blobs
func tarball(blobs []tarrableBlob) ([]byte, error) {
	buf := &bytes.Buffer{}
	w := tar.NewWriter(buf)
	defer w.Close()
	for _, tb := range blobs {
		th := tar.Header{
			Typeflag: tar.TypeReg,
			Name:     tb.oid,
			Size:     int64(len(tb.content)),
		}
		if err := w.WriteHeader(&th); err != nil {
			return nil, err
		}
		if _, err := w.Write(tb.content); err != nil {
			return nil, err
		}
	}
	if err := w.Flush(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
