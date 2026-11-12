package exp

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestExpFlagKey(t *testing.T) {
	tests := []struct {
		name string
		flag Flag
		want string
	}{
		{
			name: "default namespace",
			flag: Flag{Name: "cca_test"},
			want: "/default/cca_test",
		},
		{
			name: "custom namespace",
			flag: Flag{Namespace: "copilot_coding_agent", Name: "test"},
			want: "/copilot_coding_agent/test",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, FlagKey(tt.flag))
		})
	}
}

func TestIsActorStaff(t *testing.T) {
	tests := []struct {
		name   string
		orgIDs []uint64
		want   bool
	}{
		{
			name:   "GitHub org member",
			orgIDs: []uint64{GHOrgID},
			want:   true,
		},
		{
			name:   "Microsoft org member",
			orgIDs: []uint64{MSOrgID},
			want:   true,
		},
		{
			name:   "Microsoft Copilot org member",
			orgIDs: []uint64{MSCopilotOrgID},
			want:   true,
		},
		{
			name:   "ArgosGH org member",
			orgIDs: []uint64{ArgosGHOrgID},
			want:   true,
		},
		{
			name:   "non-staff org",
			orgIDs: []uint64{99999},
			want:   false,
		},
		{
			name:   "empty orgs",
			orgIDs: []uint64{},
			want:   false,
		},
		{
			name:   "nil orgs",
			orgIDs: nil,
			want:   false,
		},
		{
			name:   "mixed orgs with one staff",
			orgIDs: []uint64{11111, GHOrgID, 22222},
			want:   true,
		},
		{
			name:   "multiple non-staff orgs",
			orgIDs: []uint64{11111, 22222, 33333},
			want:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, IsActorStaff(tt.orgIDs))
		})
	}
}
