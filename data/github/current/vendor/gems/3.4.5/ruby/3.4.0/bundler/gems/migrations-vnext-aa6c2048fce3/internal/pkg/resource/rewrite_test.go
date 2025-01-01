package resource

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_rewriteBaseURL(t *testing.T) {
	type args struct {
		in     string
		oldURL string
		newURL string
	}
	tests := []struct {
		name string
		args args
		want string
	}{
		{
			name: "no change",
			args: args{
				in:     "no url to change here",
				oldURL: "http://old.com",
				newURL: "http://new.com",
			},
			want: "no url to change here",
		},
		{
			name: "change",
			args: args{
				in:     "this url should change: http://old.com/1/2/3 multiple times http://old.com",
				oldURL: "http://old.com",
				newURL: "http://new.com",
			},
			want: "this url should change: http://new.com/1/2/3 multiple times http://new.com",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, rewriteBaseURL(tt.args.in, tt.args.oldURL, tt.args.newURL), "rewriteBaseURL(%v, %v, %v)", tt.args.in, tt.args.oldURL, tt.args.newURL)
		})
	}
}
