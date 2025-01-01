package query

import (
	"math"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

type pageRequest interface {
	GetPageNumber() int32
	GetResultsPerPage() int32
}

type page struct {
	docs      []*pb.GitDocumentMatch
	page      uint32
	pageCount uint32
}

// Select the relevant documents based on pagination rules
// TODO: use the page_token to correctly implement pagination
func selectPage(documents []*pb.GitDocumentMatch, req pageRequest) page {
	start := req.GetPageNumber() * req.GetResultsPerPage()
	end := start + req.GetResultsPerPage()
	if start > int32(len(documents)) {
		start = int32(len(documents))
	}
	if end > int32(len(documents)) {
		end = int32(len(documents))
	}

	return page{
		docs:      documents[start:end],
		page:      uint32(req.GetPageNumber()),
		pageCount: uint32(math.Ceil(float64(len(documents)) / float64(req.GetResultsPerPage()))),
	}
}
