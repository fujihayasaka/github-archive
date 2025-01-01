package geyser

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGeneralSyntax(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo`,
		`+content:"foo"`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo "bar("`,
		`+content:( +"foo" +"bar(" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`language_id:777 -language_id:666`,
		`( #language_id:"777" -language_id:"666" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo bar language_id:777 language_id:778 -language_id:666 -language_id:667`,
		`( +content:( +"foo" +"bar" ) #language_id:( "777" "778" ) -language_id:( "666" "667" ) )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo notaqualifier:foo`,
		`+content:( +"foo" +"notaqualifier:foo" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`-foo`,
		`( -content:"foo" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`NOT foo`,
		`( -content:"foo" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`-foo -path:bar`,
		`( -content:"foo" -path:"bar" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`-foo -bar baz -path:bar`,
		`( -content:( "foo" "bar" ) +content:"baz" -path:"bar" )`,
	)
}

func TestQualifier_Path(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo path:/yabba/dabba/doo/`,
		`( +content:"foo" #path:"/yabba/dabba/doo/" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo path:/`,
		`( +content:"foo" #is_root_file:"true" )`,
	)
}

func TestQualifier_Fork(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo fork:true`,
		`( +content:"foo" #fork:"true" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo fork:only`,
		`( +content:"foo" #fork:"true" )`,
	)
	requireExpectedError(t,
		`foo fork:spoon`,
		"value for `fork` qualifier must be one of `true` or `only`, found `spoon`",
	)
	requireExpectedError(t,
		`foo fork:true fork:only`,
		"`fork` qualifier can only be used once",
	)
}

func TestQualifier_In(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo in:path`,
		`+path.split:"foo"`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo in:file`,
		`+content:"foo"`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo bar in:path`,
		`+path.split:( +"foo" +"bar" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo in:path path:bar`,
		`( +path.split:"foo" #path:"bar" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo in:path,file`,
		// this is confusing to read, but it basically says that if someone is searching for `foo bar` in both the path
		// and file then we must match both terms in `path.split` OR in `content`
		`+( ( +path.split:"foo" ) ( +content:"foo" ) )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo bar in:path,file`,
		// this is confusing to read, but it basically says that if someone is searching for `foo bar` in both the path
		// and file then we must match both terms in `path.split` OR in `content`
		`+( ( +path.split:"foo" +path.split:"bar" ) ( +content:"foo" +content:"bar" ) )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo bar in:path,file path:thing`,
		`( +( ( +path.split:"foo" +path.split:"bar" ) ( +content:"foo" +content:"bar" ) ) #path:"thing" )`,
	)
	requireExpectedError(t,
		`foo in:path in:file`,
		"`in` qualifier can only be used once",
	)
}

func TestQualifier_FilenameAndExtension(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`filename:stuff`,
		`#filename:"stuff"`,
	)
	requireExpectedParseEqualsActualParse(t,
		`extension:.js`,
		`#extension:"js"`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo extension:js`,
		`( +content:"foo" #extension:"js" )`,
	)
}

func TestQualifier_RepoOrgUser(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo repo_id:3`,
		`( +content:"foo" #repository_id:"3" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo user_id:3`,
		`( +content:"foo" #owner_id:"3" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo org_id:3`,
		`( +content:"foo" #owner_id:"3" )`,
	)
	requireExpectedParseEqualsActualParse(t,
		`foo repo_id:3 org_id:4 user_id:5`,
		`( +content:"foo" #repository_id:"3" #owner_id:( "4" "5" ) )`,
	)
}

func TestIgnoreSort(t *testing.T) {
	requireExpectedParseEqualsActualParse(t,
		`foo sort:indexed-asc bar`,
		`+content:( +"foo" +"bar" )`,
	)
}

func requireExpectedParseEqualsActualParse(t *testing.T, queryString, expectedParse string) {
	t.Helper()

	t.Run(queryString, func(t *testing.T) {
		pq, err := ParseQuery(queryString)
		require.NoError(t, err)
		actualParse := pq.TestString(t)
		require.Equal(t, expectedParse, actualParse, "debug output for ParsedQuery didn't match: expected: %s | got: %s", expectedParse, actualParse)
	})
}

func requireExpectedError(t *testing.T, queryString, expectedError string) {
	t.Helper()

	t.Run(queryString, func(t *testing.T) {
		_, err := ParseQuery(queryString)
		require.Error(t, err)
		require.Equal(t, expectedError, err.Error())
	})
}
