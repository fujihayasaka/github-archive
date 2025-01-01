package logger

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/github/go-log"
)

// AdaptToFieldLogger transforms a Logger into a `log.FieldLogger`.
func AdaptToFieldLogger(ctx context.Context, log Logger) log.FieldLogger {
	return &adapted{ctx: ctx, log: log}
}

type adapted struct {
	ctx context.Context
	log Logger
	kvs []kvp.Field
}

func (ad *adapted) Add(_ ...kvp.Field) { panic("don't use this API") }

func (ad *adapted) With(fields ...kvp.Field) log.FieldLogger {
	return &adapted{ctx: ad.ctx, log: ad.log, kvs: append(ad.kvs, fields...)}
}

func (ad *adapted) Debug(msg string, fields ...kvp.Field) {
	ad.log.Debug(ad.ctx, msg, append(ad.kvs, fields...)...)
}

func (ad *adapted) Info(msg string, fields ...kvp.Field) {
	ad.log.Log(ad.ctx, msg, append(ad.kvs, fields...)...)
}

func (ad *adapted) Error(msg string, fields ...kvp.Field) {
	ad.log.Error(ad.ctx, msg, append(ad.kvs, fields...)...)
}
