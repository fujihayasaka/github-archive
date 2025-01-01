package migrationctx

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

func TestNamespace(t *testing.T) {
	type args struct {
		d MigrationContextGetter
	}
	tests := []struct {
		name    string
		args    args
		want    string
		wantErr bool
	}{
		{
			name: "valid resource",
			args: args{
				d: &v1.Resource{
					MigrationContext: &v1.MigrationContext{EnterpriseId: 1},
				},
			},
			want:    "enterprise:1",
			wantErr: false,
		},
		{
			name: "invalid resource",
			args: args{
				d: &v1.Resource{},
			},
			want:    "",
			wantErr: true,
		},
		{
			name: "valid event",
			args: args{
				d: &v1.Event{
					MigrationContext: &v1.MigrationContext{EnterpriseId: 1},
				},
			},
			want:    "enterprise:1",
			wantErr: false,
		},
		{
			name: "invalid event",
			args: args{
				d: &v1.Event{},
			},
			want:    "",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Namespace(tt.args.d)
			if (err != nil) != tt.wantErr {
				t.Errorf("Namespace() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("Namespace() got = %v, want %v", got, tt.want)
			}
		})
	}
}
