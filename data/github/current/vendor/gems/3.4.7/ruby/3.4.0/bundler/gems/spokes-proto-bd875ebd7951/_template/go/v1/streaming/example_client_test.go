package streaming_test

import (
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/github/spokes-proto/gen/go/v1/streaming"
	"github.com/github/spokes-proto/gen/go/v1/types"
)

func Example_client() {
	// Build a request message.
	req := streaming.NewBatchBlobsRequest(
		types.NewRequestContext(types.RequestContext_QUALITY_OF_SERVICE_DELAYABLE),
		types.NewRepository(1),
		[]*types.ObjectID{
			types.NewObjectID("1b70b9e5eb39148d8b78aa22b5547df7892e2c60"),
			types.NewObjectID("8f828136c2b53856f1b511dba33fda1cb5a342f4"),
			types.NewObjectID("f10a052adcbfcd6320cf444d0e61dd9e4886497f"),
		},
	)

	// Build an HTTP request.
	httpreq, _ := streaming.NewBatchBlobsHTTPRequest(req, "https://spokesd.internal.github.net")

	// Get the response.
	httpresp, _ := http.DefaultClient.Do(httpreq)
	defer httpresp.Body.Close()

	// Read the entries.
	tr, _ := streaming.GetBatchBlobsTarReader(httpresp)
	for hdr, err := tr.Next(); err != io.EOF; hdr, err = tr.Next() {
		fmt.Printf("===== blob %q =====\n", hdr.Name)
		io.Copy(os.Stdout, tr)
		fmt.Println("")
	}
}
