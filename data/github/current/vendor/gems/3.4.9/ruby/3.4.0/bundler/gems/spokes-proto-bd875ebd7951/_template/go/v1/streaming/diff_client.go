package streaming

import (
	"bytes"
	"io"
	"fmt"
	"net/http"

	"github.com/twitchtv/twirp"
)

const (
	ReadRawDiffRequestPath = "/streaming/v1/diffs/raw"
)

func NewReadRawDiffHTTPRequest(req *ReadRawDiffRequest, baseURL string) (*http.Request, error) {
	return NewReadRawDiffHTTPRequestCustom(req, baseURL, ProtobufContentType, "application/octet-stream")
}

func NewReadRawDiffHTTPRequestCustom(req *ReadRawDiffRequest, baseURL, requestContentType, responseContentType string) (*http.Request, error) {
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

	if responseContentType != "application/octet-stream" {
		return nil, fmt.Errorf("unsupported response content type %q", responseContentType)
	}

	url := sanitizeBaseURL(baseURL) + ReadRawDiffRequestPath

	httpreq, err := http.NewRequest("POST", url, bytes.NewReader(reqData))
	if err != nil {
		return nil, err
	}
	httpreq.Header.Set("Content-Type", requestContentType)
	httpreq.Header.Set("Accept", responseContentType)
	return httpreq, nil
}

// GetReadRawDiffResponse is a helper function that reads the entire response
// body and returns the raw diff as a byte slice (or an error for non-200
// responses)
func GetReadRawDiffResponse(resp *http.Response) ([]byte, error) {
	if resp.StatusCode != http.StatusOK {
		return nil, errorFromResponse(resp)
	}
	contentType := resp.Header.Get("Content-Type")
	if contentType != "application/octet-stream" {
		return nil, twirp.InternalError(fmt.Sprintf("unexpected response content-type %q", contentType))
	}
	
	defer resp.Body.Close()
	buf, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return buf, nil
}
