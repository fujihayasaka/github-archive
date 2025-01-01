package streaming

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"

	"github.com/golang/protobuf/jsonpb"
	"github.com/golang/protobuf/proto"
)

func ReadRawDiffServerRequest(httpreq *http.Request) (*ReadRawDiffRequest, error) {
	var req ReadRawDiffRequest

	contentType := httpreq.Header.Get("Content-Type")
	i := strings.Index(contentType, ";")
	if i == -1 {
		i = len(contentType)
	}

	switch strings.TrimSpace(strings.ToLower(contentType[:i])) {
	case JSONContentType:
		unmarshaler := jsonpb.Unmarshaler{AllowUnknownFields: true}
		if err := unmarshaler.Unmarshal(httpreq.Body, &req); err != nil {
			return nil, malformedRequestError("the json request could not be decoded")
		}
	case ProtobufContentType:
		buf, err := ioutil.ReadAll(httpreq.Body)
		if err != nil {
			return nil, wrapInternal(err, "failed to read request body")
		}
		if err := proto.Unmarshal(buf, &req); err != nil {
			return nil, malformedRequestError("the protobuf request could not be decoded")
		}
	default:
		msg := fmt.Sprintf("unrecognized request content-type %q", contentType)
		return nil, badRouteError(msg, httpreq.Method, httpreq.URL.Path)
	}

	return &req, nil
}
