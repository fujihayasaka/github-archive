package hydro

import (
	"io"
	"log"
)

var nilLogger Logger = log.New(io.Discard, "", 0)

// Logger is the interface that wraps the standard log.Logger methods.
type Logger interface {
	Print(...interface{})
	Printf(string, ...interface{})
	Println(...interface{})

	Panic(...interface{})
	Panicf(string, ...interface{})
	Panicln(...interface{})

	Fatal(...interface{})
	Fatalf(string, ...interface{})
	Fatalln(...interface{})
}
