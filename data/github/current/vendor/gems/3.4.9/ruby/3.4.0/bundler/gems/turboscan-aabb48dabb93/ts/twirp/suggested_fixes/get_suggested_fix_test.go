package suggested_fixes

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"

	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/stretchr/testify/require"
)

func TestGetSuggestedFix_Valid(t *testing.T) {
	db, ctx, twirpServ, mockSpokes, _, _, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	dbtest.RequireCreate(t, db, sfa)

	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		HeadCommitOid: string(sfa.PhysicalAlert.Analysis.CommitOid),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("beef"))

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
	require.False(t, res.SuggestedFixAlerts[alertNo].SuggestedFix.Outdated)
}

func TestGetSuggestedFix_FileChanged(t *testing.T) {
	db, ctx, twirpServ, mockSpokes, _, _, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	dbtest.RequireCreate(t, db, sfa)

	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		HeadCommitOid: string(sfa.PhysicalAlert.Analysis.CommitOid),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("no beef"))

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
}

func TestGetSuggestedFix_Invalid(t *testing.T) {
	db, ctx, twirpServ, _, _, _, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	sfa.SuggestedFix = nil
	sfa.SetState(ts.SuggestedFixAlertStateInvalid, nil)
	dbtest.RequireCreate(t, db, sfa)

	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		HeadCommitOid: string(sfa.PhysicalAlert.Analysis.CommitOid),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
}

func TestGetSuggestedFix_Error(t *testing.T) {
	db, ctx, twirpServ, _, _, _, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	sfa.SuggestedFix = nil
	sfa.SetState(ts.SuggestedFixAlertStateError, nil)
	dbtest.RequireCreate(t, db, sfa)

	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		HeadCommitOid: string(sfa.PhysicalAlert.Analysis.CommitOid),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
}

func TestGetSuggestedFix_Applied(t *testing.T) {
	db, ctx, twirpServ, mockSpokes, _, _, _ := setupService(t)
	alertNo := uint32(1)

	ref := []byte("refs/heads/ref1")

	tool := &ts.Tool{CanonicalName: "CodeQL command-line toolchain"}
	dbtest.RequireCreate(t, db, tool)

	tv := &ts.ToolVersion{Name: ts.ToolName("CodeQL"), ToolID: tool.ID, SemanticVersion: "2.0.1"}
	dbtest.RequireCreate(t, db, tv)

	initialAnalysis := &ts.Analysis{
		CommitOid:          "xxx",
		Ref:                ref,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		MostRecent:         false,
		AnalysisComplete:   true,
		ToolVersion:        tv,
	}
	dbtest.RequireCreate(t, db, initialAnalysis)

	sfa := setupAlert(t, db, alertNo, "main.js", initialAnalysis, "js/reflected-xss", 1)
	sfa.SetState(ts.SuggestedFixAlertStateApplied, nil)
	dbtest.RequireCreate(t, db, sfa)

	mostRecentAnalysis := &ts.Analysis{
		CommitOid:          "yyy",
		Ref:                ref,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		MostRecent:         true,
		AnalysisComplete:   true,
		ToolVersion:        tv,
	}
	dbtest.RequireCreate(t, db, mostRecentAnalysis)

	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  1,
		HeadCommitOid: mostRecentAnalysis.CommitOid.String(),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(mostRecentAnalysis.CommitOid), []byte("this file was changed"))

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
	require.True(t, res.SuggestedFixAlerts[alertNo].SuggestedFix.Outdated)
}

func TestGetSuggestedFix_Outdated(t *testing.T) {
	db, ctx, twirpServ, mockSpokes, _, _, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	dbtest.RequireCreate(t, db, sfa)

	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GetSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		HeadCommitOid: string(sfa.PhysicalAlert.Analysis.CommitOid),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("this file was changed"))

	res, err := twirpServ.GetSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixAlerts, 1)
	require.True(t, res.SuggestedFixAlerts[alertNo].SuggestedFix.Outdated)
}
