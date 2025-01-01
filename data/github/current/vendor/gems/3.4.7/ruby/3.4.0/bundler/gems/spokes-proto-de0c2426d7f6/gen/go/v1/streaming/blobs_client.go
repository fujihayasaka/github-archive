package streaming

import (
	"archive/tar"
	"bytes"
	"fmt"
	"net/http"

	"github.com/golang/protobuf/jsonpb"
	"github.com/golang/protobuf/proto"
	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

const (
	JSONContentType     = "application/json"
	ProtobufContentType = "application/protobuf"
	TarContentType      = "application/tar"

	BatchBlobsRequestPath = "/streaming/v1/blobs"

	RepositoryBlobRequestPath = "/streaming/v1/repositories/%v/blobs/%s"
	GistBlobRequestPath       = "/streaming/v1/gists/%v/blobs/%s"
)

// NewBlobHTTPRequest generates a new HTTP request for a single blob.
func NewBlobHTTPRequest(repository *types.Repository, oid *types.ObjectID, baseURL string) (*http.Request, error) {
	var pathFormat string
	switch repository.GetType() {
	case types.Repository_TYPE_REPOSITORY:
		pathFormat = RepositoryBlobRequestPath
	case types.Repository_TYPE_GIST:
		pathFormat = GistBlobRequestPath
	default:
		return nil, fmt.Errorf("unsupported repository type %v", repository.GetType())
	}
	url := sanitizeBaseURL(baseURL) + fmt.Sprintf(pathFormat, repository.GetId(), oid.GetId())

	return http.NewRequest("GET", url, nil)
}

// NewBatchBlobsHTTPRequest generates a new HTTP request for a batch blob request.
func NewBatchBlobsHTTPRequest(req *BatchBlobsRequest, baseURL string) (*http.Request, error) {
	return NewBatchBlobsHTTPRequestCustom(req, baseURL, ProtobufContentType, TarContentType)
}

// NewBatchBlobsHTTPRequestCustom generates a new HTTP request for a batch blob request with custom request and response types.
func NewBatchBlobsHTTPRequestCustom(req *BatchBlobsRequest, baseURL, requestContentType, responseContentType string) (*http.Request, error) {
	var reqData []byte

	switch requestContentType {
	case JSONContentType:
		r, err := marshalJSON(req)
		if err != nil {
			return nil, err
		}
		reqData = r
	case ProtobufContentType:
		r, err := marshalProtobuf(req)
		if err != nil {
			return nil, err
		}
		reqData = r
	default:
		return nil, fmt.Errorf("unsupported request content type %q", requestContentType)
	}

	if responseContentType != TarContentType {
		return nil, fmt.Errorf("unsupported response content type %q", responseContentType)
	}

	url := sanitizeBaseURL(baseURL) + BatchBlobsRequestPath

	httpreq, err := http.NewRequest("POST", url, bytes.NewReader(reqData))
	if err != nil {
		return nil, err
	}
	httpreq.Header.Set("Content-Type", requestContentType)
	httpreq.Header.Set("Accept", responseContentType)
	return httpreq, nil
}

// GetBatchBlobsTarReader sets up a tar.Reader for a response after checking for errors. The caller is responsible for closing the response body when processing is finished.
func GetBatchBlobsTarReader(resp *http.Response) (*tar.Reader, error) {
	if resp.StatusCode != http.StatusOK {
		return nil, errorFromResponse(resp)
	}
	contentType := resp.Header.Get("Content-Type")
	if contentType != TarContentType {
		return nil, twirp.InternalError(fmt.Sprintf("unexpected response content-type %q", contentType))
	}
	return tar.NewReader(resp.Body), nil
}

func marshalJSON(message proto.Message) ([]byte, error) {
	marshaler := jsonpb.Marshaler{OrigName: true}
	var buf bytes.Buffer
	if err := marshaler.Marshal(&buf, message); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func marshalProtobuf(message proto.Message) ([]byte, error) {
	return proto.Marshal(message)
}
