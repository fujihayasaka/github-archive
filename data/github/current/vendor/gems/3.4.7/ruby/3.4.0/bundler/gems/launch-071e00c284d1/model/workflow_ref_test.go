package model

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_parseWorkflowRef(t *testing.T) {
	tests := []struct {
		input   string
		want    *WorkflowRef
		wantErr string
	}{
		{
			input:   ".github/workflows/subdir/cd-node.yml@v1.0",
			wantErr: "workflows must be defined at the top level of the .github/workflows/ directory",
		},
		{
			input:   ".github/workflows/subdir/subsubdir/cd-node.yml@v1.0",
			wantErr: "workflows must be defined at the top level of the .github/workflows/ directory",
		},
		{
			input:   ".github/workflows/cd-node.yml@v1.0",
			wantErr: "references to workflows must be prefixed with format 'owner/repository/' or './' for local workflows",
		},
		{
			input:   "actions/starter-workflows/elsewhere/cd-node.yml@v1.0",
			wantErr: "references to workflows must be rooted in '.github/workflows'",
		},
		{
			input: "actions/starter-workflows/.github/workflows/cd-node.yml@v1.0",
			want: &WorkflowRef{
				Owner: "actions",
				Repo:  "starter-workflows",
				Path:  ".github/workflows/cd-node.yml",
				Version: VersionRef{
					GitRef: pstring("v1.0"),
				},
			},
		},
		{
			input: "./.github/workflows/cd-node.yml",
			want: &WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/cd-node.yml",
				Version: VersionRef{},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got, err := ParseWorkflowRef(tt.input)
			if tt.wantErr != "" {
				require.EqualError(t, err, tt.wantErr)
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.want, got)
			}
		})
	}
}

func Test_parseWorkflowRef_InvalidRefs(t *testing.T) {
	invalidRefs := []string{
		// invalid nwo
		".github/workflows@",
		"./.github/workflows/myworkflow.yml@v1",
		"owner/invalid*repo!name/.github/workflows/myworkflow.yml@v1.1",
		"owner/repo/name.github/workflows/myworkflow.yml@v1.1",
		"//.github/workflows/myworkflow.yml@v",
		"act42s/s|arter-workflows/.github/workflows/myworkflow@v1.1",
		"owner/star�er-wo�kflows/.github/workflows/myworkflow.yml@v1.1",
		"owner/starter}}}}kflows/.github/workflows/myworkflow.yml@v1.1",
		"`ctions/repo/.github/workflows/myworkflow.yml@v1.1",
		"t�stowner42/repo/.github/workflows/myworkflow.yml@rm",
		"ow~erRandomString/repo/.github/workflows/myworkflow.yml@v1.1",
		"act42sĵ/repo/.github/workflows/myworkflow.yml@v1.1",
		"act42s/starter-w~~~~~o[rkflows/.github/workflows/myworkflow.yml@v1.1",
		"act4s/repo/.github/workflows/myworkflow.yml@v1.1",
		"owner/asetarter-workflo^s/.github/workflows/mywofrkl.yml@v1.1",
		"actions/repo/.github/workflows/mywoitflow.yml@dir/path",      // control chars 0x10 ^P^P^P^P^P^P
		"owner/starterworkflows/.github/workflows-lab/myworkfl4w.yml@v1.1", // contro char 0x01 ^A
		"owner/starter-�orkflows/.github/workflows-lab/myworkflow.yml@v1.1",
		"actions--invalid_name/starterworkflows/.github/workflows/myworkflow.yml@v1.1", // control char 0x18 ^X
		"owner/repo?sitory/.github/workflows/myworkflow.yml@v1.1",
		"owner/repo1/repo2/.github/workflows/myworkflow.yml@v1.1",
		"owner/repo  sitory/.github/workflows/myworkflow.yml@v1.1",

		// invalid version
		"owner/repo/.github/workflows/myworkflow.yml",
		"owner/repo/.github/workflows/myworkflow.yml@",
		"owner/repo/.github/workflows/myworkflow.yml@?",
		"owner/repo/.github/workflows/myworkflow.yml@[",
		"owner/repo/.github/workflows/myworkflow.yml@v1*1",
		"owner/repo/.github/workflows/myworkflow.yml@@",
		"owner/repo/.github/workflows/myworkflow.yml@.",
		"owner/repo/.github/workflows/myworkflow.yml@asdf..asdf",
		"owner/repo/.github/workflows/myworkflow.yml@asdf//asdf",
		"owner/repo/.github/workflows/myworkflow.yml@dir/path.lock",
		"owner/repo/.github/workflows/myworkflow.yml@ && rm -rf", // whitespace
		"owner/repo/.github/workflows/myworkflow.yml@main && rm -rf /",
		"owner/repo/.github/workflows/myworkflow.yml@v1\\1",
		"owner/repo/.github/workflows/myworkflow.yml@/kfuuu.uu",
		"owner/repo/.github/workflows/myworkflow.yml@/////-r,,,,,,f",
		"owner/repo/.github/workflows/myworkflow.yml@dir/..22",
		"owner/repo/.github/workflows/myworkflow.yml@v1.1.",

		// invalid version: ascii control characters
		"owner1/sta_ter-workflows/.github/workflows/mywTTTorw.yml@kfuuuuu\x00ow",         // 0x00 NUL
		"actions/starter-workflows/.github/workflows/myworkflow.yml@dir/pat.locworkflk", // 0x10 ^P
		"owner1/starter-workflows/.github/workflows/myworkflow.yml@/�.",                 // 0x7F ^?
		"act42s/s|arter-workflows/.github/workflows/myworfloIIyml@v1.1",

		// invalid path
		"owner/repo.github/workflows/myworkflow.yml@v1.1",
		"owner/repo/.github/workflows@v1.1",
		"owner/repo/.github/workflow/workflow.yml@v",
		"owner/repo/.github/workflows-lag/workflow.yml@v",
		"owner/repo/.github/workflows/moredir/myworkflow.yml@v1.1",
		"owner/repo/.github/workflows/myworkflow.ymlz@v1.1",
		"owner/repo/.github/workflows/myworkflow.woyml@v1.1",
		"owner/repo/.github/workflows/.yml@v1.1",
		"owner/repo/.github/workflows/myworkflow.yml///@v0.1",
		"owner/repo/.github/workflows/.github/workflows/.github/workflows/myworkflow.yml@v0.1",
		"owner/repo/.github/workflows-lab/myworkflow.y~l@v1.1",
		"owner/repo/.github/workflowsKmyworhflow.yml@v1",
		"owner/repo/.github/workflows-lab/myworkflow.yml@v1.1",        // control chars 0x7F ^?^?^?
		"actions/starter-workflowP/.github/workflows myworkflow.yml@ver", // whitespace

	}
	for _, refs := range invalidRefs {
		t.Run(refs, func(t *testing.T) {
			_, err := ParseWorkflowRef(refs)
			require.Error(t, err)
		})
	}

	validRefs := []string{
		// nwo
		"./.github/workflows/ci.yml",
		"act42s/startePPPPPPPPr-workflows/.github/workflows/myworkflow.yml@v1.1",
		"s/tarer-workflows/.github/workflows/myworkflow.yml@v1.1",
		"actions/startAr-workflows/.github/workflows/myworkflow.yml@v1.1",
		"owner1/starter-workflows/.github/workflows/myworkflow.yml@v1.1",
		"0000/0/.github/workflows/myworkflow.yml@v1.1",
		"ownerRmndomString/starter-workflows/.github/workflows/myworkflow.yml@v1.1",
		"0a-o/f/.github/workflows/myworkflow.yml@v1.1",
		"ctio/f/.github/workflows/myworkflow.yml@v1.1",
		"owner1/sta_ter-workflows/.github/workflows/myworkflow.yml@v1.1",

		// version
		"owner/repo/.github/workflows/myworkflow.yml@v1.1",
		"owner/repo/.github/workflows/myworkflow.yml@76d4cbce60ea9a14ce679b44016fdfb4a3670bde",
		"owner/repo/.github/workflows/myworkflow.yml@dir/pthub/ock",
		"owner/repo/.github/workflows/myworkflow.yml@dir/p",
		"owner/repo/.github/workflows/myworkflow.yml@d",
		"owner/repo/.github/workflows/myworkflow.yml@dir",
		"owner/repo/.github/workflows/myworkflow.yml@v1.������1",
		"owner/repo/.github/workflows/myworkflow.yml@��n",
		"owner/repo/.github/workflows/myworkflow.yml@0",
		"owner/repo/.github/workflows/myworkflow.yml@dX�i�irn76N4cbce60ea9a14ce679b44016fdfb��������e",
		"owner/repo/.github/workflows/myworkflow.yml@dirn76d4cbce60ea4ce6\"9b44016fdfb4a36������",
		"owner/repo/.github/workflows/myworkflow.yml@-/kfuuu.uu",

		// path
		"owner/repo/.github/workflows/my workflow.yml@v1.1",
		"owner/repo/.github/workflows-lab/my workflow.yml@v1.1",
		"owner/repo/.github/workflows/::::::flsw.yml@v1.1",
		"owner/repo/.github/workflows/m\\workflow.yml@v1.1",
		"owner/repo/.github/workflows/*.yml@v1.1",
		"owner/repo/.github/workflows/m�workflow.yml@v1.1",
		"owner/repo/.github/workflows/�.yml@v1.1",
		"owner/repo/.github/workflows/mywTTTorw.yml@v1.1",
	}
	for _, refs := range validRefs {
		t.Run(refs, func(t *testing.T) {
			_, err := ParseWorkflowRef(refs)
			require.NoError(t, err)
		})
	}

}

func Test_WorkflowRef_String(t *testing.T) {
	tests := []struct {
		desc  string
		input *WorkflowRef
		want  string
	}{
		{
			desc: "regular nwo with version",
			input: &WorkflowRef{
				Owner: "owner",
				Repo:  "repo",
				Path:  "path",
				Version: VersionRef{
					GitRef: pstring("v1.1"),
				},
			},
			want: "owner/repo/path@v1.1",
		},
		{
			desc: "regular nwo without version",
			input: &WorkflowRef{
				Owner:   "owner",
				Repo:    "repo",
				Path:    "path",
				Version: VersionRef{},
			},
			want: "owner/repo/path",
		},
		{
			desc: "blank nwo with version",
			input: &WorkflowRef{
				Owner: "",
				Repo:  "",
				Path:  "path",
				Version: VersionRef{
					GitRef: pstring("v1.1"),
				},
			},
			want: "path@v1.1",
		},
		{
			desc: "dot nwo with version",
			input: &WorkflowRef{
				Owner: ".",
				Repo:  ".",
				Path:  "path",
				Version: VersionRef{
					GitRef: pstring("v1.1"),
				},
			},
			want: "./path@v1.1",
		},
	}
	for _, tt := range tests {
		{
			t.Run(tt.desc, func(t *testing.T) {
				require.Equal(t, tt.want, tt.input.String())
			})

		}
	}
}

func pstring(str string) *string { return &str }
