package cmd

import (
	"github.com/github/authnd/cmd/authnd-client/cmd/mobileauthcli"
	"github.com/github/authnd/cmd/authnd-client/cmd/mobiledevicecli"
	"github.com/github/authnd/cmd/authnd-client/cmd/storecli"
	"github.com/spf13/cobra"
	flag "github.com/spf13/pflag"
)

var (
	verbose bool
)

// RootCmd represents the base command when called without any subcommands
var RootCmd = &cobra.Command{
	Use:           "authnd-client",
	Short:         "Authentication Service CLI",
	Long:          `This tool provides a CLI interface to the Authentication Service.`,
	SilenceErrors: true,
	SilenceUsage:  true,
}

// based off of the default usage template from Cobra, but specialized
// to extra common flags (i.e. hmac auth key) for readability
// https://github.com/spf13/cobra/blob/178edbb247f35e466578211dcf5f4892dbbd369b/command.go#L491-L514
const usage = `Usage:{{if .Runnable}}
  {{.UseLine}}{{end}}{{if .HasAvailableSubCommands}}
  {{.CommandPath}} [command]{{end}}{{if gt (len .Aliases) 0}}

Aliases:
  {{.NameAndAliases}}{{end}}{{if .HasExample}}

Examples:
{{.Example}}{{end}}{{if .HasAvailableSubCommands}}

Available Commands:{{range .Commands}}{{if (or .IsAvailableCommand (eq .Name "help"))}}
  {{rpad .Name .NamePadding }} {{.Short}}{{end}}{{end}}{{end}}

{{if hasUniqueFlags . -}}
Flags:
{{ (uniqueFlags .).FlagUsages | trimTrailingWhitespaces}}
{{- end}}

{{if hasCommonFlags . -}}
Global Flags:
{{ (commonFlags .).FlagUsages | trimTrailingWhitespaces}}
{{- end}}

{{- if .HasHelpSubCommands}}
Additional help topics:{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}
  {{rpad .CommandPath .CommandPathPadding}} {{.Short}}{{end}}{{end}}{{end}}{{if .HasAvailableSubCommands}}

Use "{{.CommandPath}} [command] --help" for more information about a command.{{end}}
`

func hasCommonFlags(cmd *cobra.Command) bool {
	return commonFlags(cmd).HasFlags()
}

func commonFlags(cmd *cobra.Command) *flag.FlagSet {
	cf := flag.NewFlagSet("common", flag.ContinueOnError)

	cf.AddFlagSet(cmd.InheritedFlags())
	cmd.LocalFlags().VisitAll(func(f *flag.Flag) {
		if isCommon(f.Name) {
			cf.AddFlag(f)
		}
	})

	return cf
}

func hasUniqueFlags(cmd *cobra.Command) bool {
	return uniqueFlags(cmd).HasFlags()
}

func uniqueFlags(cmd *cobra.Command) *flag.FlagSet {
	uf := flag.NewFlagSet("unique", flag.ContinueOnError)
	cmd.LocalFlags().VisitAll(func(f *flag.Flag) {
		if !isCommon(f.Name) {
			uf.AddFlag(f)
		}
	})
	return uf
}

func isCommon(name string) bool {
	switch name {
	case "addr", "catalog-service", "environment", "help", "hmac-key", "ip", "request-hmac", "verbose":
		return true
	default:
		return false
	}
}

func init() {
	cobra.AddTemplateFunc("hasUniqueFlags", hasUniqueFlags)
	cobra.AddTemplateFunc("uniqueFlags", uniqueFlags)
	cobra.AddTemplateFunc("hasCommonFlags", hasCommonFlags)
	cobra.AddTemplateFunc("commonFlags", commonFlags)
	RootCmd.SetUsageTemplate(usage)

	RootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "Verbosely log")

	RootCmd.AddCommand(NewAuthenticateCommand())
	RootCmd.AddCommand(NewExchangeCommand())
	RootCmd.AddCommand(NewChatopCommand())
	RootCmd.AddCommand(NewIssueCommands()...)
	RootCmd.AddCommand(NewRevokeCommand())
	RootCmd.AddCommand(NewVerifyCommand())
	RootCmd.AddCommand(NewFindCommand())
	RootCmd.AddCommand(mobiledevicecli.NewMobileDeviceRootCmd())
	RootCmd.AddCommand(mobileauthcli.NewMobileAuthRootCmd())
	RootCmd.AddCommand(storecli.NewStoreRootCmd())
}
