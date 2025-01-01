package streaming_test

import (
	"archive/tar"
	"fmt"
	"net/http"

	"github.com/github/spokes-proto/gen/go/v1/streaming"
	"github.com/twitchtv/twirp"
)

func Example_server() {
	http.HandleFunc(streaming.BatchBlobsRequestPath, func(w http.ResponseWriter, r *http.Request) {
		req, err := streaming.ReadBatchBlobsRequest(r)
		if err != nil {
			twirp.WriteError(w, err)
			return
		}

		// This should be replaced by real parsing of the Accept header.
		accept := r.Header.Get("Accept")
		if accept != streaming.TarContentType && accept != "*/*" {
			twirp.WriteError(w, twirp.NewError(twirp.Malformed, "no acceptable content type found in accept request header"))
			return
		}

		// Remember to set the content-type of the response.
		w.Header().Set("Content-Type", streaming.TarContentType)

		// Calling Flush indicates that the response should be chunked and streamed.
		f := w.(http.Flusher)
		f.Flush()

		tw := tar.NewWriter(w)

		for _, oid := range req.Oids {
			output := fmt.Sprintf("(insert contents of %s here)", oid.GetId())

			_ = tw.WriteHeader(&tar.Header{Name: oid.GetId(), Size: int64(len(output))})
			f.Flush()

			_, _ = tw.Write([]byte(output))
			_ = tw.Flush()
			f.Flush()
		}
	})
}
