package kafkalog

import (
	"fmt"

	"github.com/github/go-kvp"
	"github.com/github/go-log"
	"github.com/github/hydro-client-go/v3/pkg/hydro"
)

type kafkaLoggerAdapter struct {
	ll log.FieldLogger
}

func AdaptFieldLoggerToKafkaLogger(ll log.FieldLogger) hydro.Logger {
	return &kafkaLoggerAdapter{ll: ll}
}

func (ll *kafkaLoggerAdapter) Print(v ...any) {
	ll.ll.Info(fmt.Sprint(v...), kvp.Bool("gh.launch.is_kafka", true))
}

func (ll *kafkaLoggerAdapter) Printf(s string, v ...any) {
	ll.ll.Info(fmt.Sprintf(s, v...), kvp.Bool("gh.launch.is_kafka", true))
}
func (ll *kafkaLoggerAdapter) Println(v ...any) {
	ll.ll.Info(fmt.Sprint(v...), kvp.Bool("gh.launch.is_kafka", true))
}

func (ll *kafkaLoggerAdapter) Panic(v ...any) {
	// NOT USED, TO BE REMOVED
	panic(v)

}
func (ll *kafkaLoggerAdapter) Panicf(s string, v ...any) {
	// NOT USED, TO BE REMOVED
	panic(fmt.Sprintf(s, v...))

}
func (ll *kafkaLoggerAdapter) Panicln(v ...any) {
	// NOT USED, TO BE REMOVED
	panic(v)
}

func (ll *kafkaLoggerAdapter) Fatal(v ...any) {
	// NOT USED, TO BE REMOVED
	panic(v)
}
func (ll *kafkaLoggerAdapter) Fatalf(s string, v ...any) {
	// NOT USED, TO BE REMOVED
	panic(fmt.Sprintf(s, v...))

}
func (ll *kafkaLoggerAdapter) Fatalln(_ ...any) {
	// NOT USED, TO BE REMOVED
}
