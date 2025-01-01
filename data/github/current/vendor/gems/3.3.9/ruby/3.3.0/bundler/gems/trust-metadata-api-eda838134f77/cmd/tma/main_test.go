package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/spf13/cobra"
	"github.com/stretchr/testify/assert"
)

func NewTestRootCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "test-cmd",
		Short: "This is a test root command which can be used as a mock",
		Run:   func(*cobra.Command, []string) {},
	}
}

func Test_initConfig(t *testing.T) {
	cmd := NewTestRootCmd()
	b := bytes.NewBufferString("")
	cmd.SetOut(b)

	// I want to test that we pick up TMA_ env variables, so let's cautiously
	// define a value for the Port config.
	// As a side effect, we are also testing that the default port value ("8080")
	// is overridden by the env variable.
	oldPortEnv := os.Getenv("TMA_API_PORT")
	defer os.Setenv("TMA_API_PORT", oldPortEnv)
	os.Setenv("TMA_API_PORT", "1234")

	// I also want to test that env variables are overridden by flags
	oldLogEnv := os.Getenv("TMA_LOG_LEVEL")
	defer os.Setenv("TMA_LOG_LEVEL", oldLogEnv)
	os.Setenv("TMA_LOG_LEVEL", "error")

	cmd.SetArgs([]string{"server", "--log-level", "info", "--mysql-user", "monalisa"})

	cmd.AddCommand(initServerCommand(func(_ *cobra.Command, _ []string) error {
		// only interested in testing initConfig, and not runServer for now, so
		// here we mock out the server command:
		fmt.Fprintf(cmd.OutOrStdout(), "Server command executed!")
		return nil
	}))
	err := cmd.Execute()
	if err != nil {
		t.Fatal(err)
	}

	assert.Equal(t, "monalisa", config.MySQLUser)
	assert.Equal(t, "1234", config.APIPort)
	assert.Equal(t, "info", config.LogLevel)

	out, err := io.ReadAll(b)
	if err != nil {
		t.Fatal(err)
	}

	assert.Equal(t, "Server command executed!", string(out), "Expected the provided func to have been executed")
}

func TestLoadVerifier(t *testing.T) {
	var tests = []struct {
		Case      string
		Cfg       configStruct
		ExpectPGI bool
		ExpectNpm bool
		ExpectGH  bool
		FulcioCN  string
		Fail      bool
	}{
		{
			Case: "Default prod",
			Cfg: configStruct{
				TUFMirror: "https://tuf-repo.github.com",
			},
			ExpectPGI: true,
			ExpectNpm: true,
			ExpectGH:  true,
			FulcioCN:  "Fulcio Intermediate l2",
			Fail:      false,
		},
		{
			Case: "Invalid stamp prod",
			Cfg: configStruct{
				TUFMirror: "https://tuf-repo.github.com",
				Stamp:     "not-a-stamp.json",
			},
			ExpectPGI: true,
			ExpectNpm: true,
			ExpectGH:  true,
			FulcioCN:  "invalid",
			Fail:      true,
		},
		{
			Case: "Invalid mirror",
			Cfg: configStruct{
				TUFMirror: "https://not-a-mirror.com",
			},
			ExpectPGI: true,
			ExpectNpm: true,
			ExpectGH:  true,
			FulcioCN:  "invalid",
			Fail:      true,
		},
		{
			Case: "Default staging",
			Cfg: configStruct{
				TUFMirror: "https://github.github.com/staging-tuf-root",
			},
			ExpectPGI: true,
			ExpectNpm: true,
			ExpectGH:  true,
			FulcioCN:  "Fulcio Intermediate l2 - staging",
			Fail:      false,
		},
		{
			Case: "staff-wus2-01 staging",
			Cfg: configStruct{
				TUFMirror: "https://github.github.com/staging-tuf-root",
				Stamp:     "staff-wus2-01",
			},
			ExpectPGI: false,
			ExpectNpm: false,
			ExpectGH:  true,
			FulcioCN:  "Fulcio Intermediate l2 - staff-wus2-01",
			Fail:      false,
		},
	}

	l, _ := log.NewFromEnv(log.WithLogLevel(log.FatalLevel))
	for _, tc := range tests {
		t.Run(tc.Case, func(t *testing.T) {
			var cfg = tc.Cfg

			tc.Cfg.TUFDirectory = t.TempDir()
			verifier, err := loadVerifier(&cfg, l)

			if tc.Fail {
				assert.Nil(t, verifier)
				assert.Error(t, err)
				return
			}

			if tc.ExpectPGI {
				assert.NotNil(t, verifier.PublicGoodTrustedMaterial())
			} else {
				assert.Nil(t, verifier.PublicGoodTrustedMaterial())
			}
			if tc.ExpectNpm {
				assert.NotNil(t, verifier.NpmTrustedMaterial())
			} else {
				assert.Nil(t, verifier.NpmTrustedMaterial())
			}
			if tc.ExpectGH {
				var ghtr = verifier.GitHubTrustedMaterial()
				var got = ghtr.FulcioCertificateAuthorities()[0].Intermediates[0].Subject.CommonName

				assert.NotNil(t, ghtr)
				assert.Equal(t, tc.FulcioCN, got)
			} else {
				assert.Nil(t, verifier.GitHubTrustedMaterial())
			}
		})
	}
}
