package attestation

import (
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"reflect"
	"testing"

	"github.com/github/trust-metadata-api/test/data"
)

func TestParseTrustedKeys(t *testing.T) {
	var pubKey crypto.PublicKey
	der, _ := pem.Decode([]byte(data.SigstoreBundlePublicKeyPEM))
	key, err := x509.ParsePKIXPublicKey(der.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	pubKey = key.(crypto.PublicKey)

	type args struct {
		keys string
	}
	tests := []struct {
		name    string
		args    args
		want    map[string]crypto.PublicKey
		wantErr bool
	}{
		{
			name:    "empty object",
			args:    args{"{}"},
			want:    map[string]crypto.PublicKey{},
			wantErr: false,
		},
		{
			name: "single key",
			args: args{
				keys: `{"` + data.SigstoreBundlePublicKeyHint + `": "` + data.SigstoreBundlePublicKeyB64 + `"}`,
			},
			want:    map[string]crypto.PublicKey{data.SigstoreBundlePublicKeyHint: pubKey},
			wantErr: false,
		},
		{
			name: "multiple keys",
			args: args{
				keys: `{"` + data.SigstoreBundlePublicKeyHint + `": "` + data.SigstoreBundlePublicKeyB64 + `","` +
					data.SigstoreBundlePublicKeyHint + `-2": "` + data.SigstoreBundlePublicKeyB64 + `"}`,
			},
			want:    map[string]crypto.PublicKey{data.SigstoreBundlePublicKeyHint: pubKey, data.SigstoreBundlePublicKeyHint + "-2": pubKey},
			wantErr: false,
		},
		{
			name: "empty string produces error",
			args: args{
				keys: "",
			},
			want:    nil,
			wantErr: true,
		},
		{
			name: "invalid json produces error",
			args: args{
				keys: data.SigstoreBundlePublicKeyPEM,
			},
			want:    nil,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseTrustedKeys(tt.args.keys)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParseTrustedKeys() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ParseTrustedKeys() = %v, want %v", got, tt.want)
			}
		})
	}
}
