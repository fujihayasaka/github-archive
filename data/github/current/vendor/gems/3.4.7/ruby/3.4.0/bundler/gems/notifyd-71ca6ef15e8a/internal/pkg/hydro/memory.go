package hydro

import "github.com/github/hydro-client-go/v7/pkg/hydro"

// BuildMemoryPublisher returns a new hydro.Publisher that writes to the provided eventChannel.
func BuildMemoryPublisher(eventChannel chan<- hydro.Message) (*hydro.Publisher, error) {
	sink, err := hydro.NewMemorySink(eventChannel)
	if err != nil {
		return nil, err
	}

	publisher, err := hydro.NewPublisher(sink, hydro.WithSiteName("localhost"))
	if err != nil {
		return nil, err
	}

	return publisher, err
}
