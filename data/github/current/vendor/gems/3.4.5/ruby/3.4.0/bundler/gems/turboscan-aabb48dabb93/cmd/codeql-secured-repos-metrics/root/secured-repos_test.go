package root

import (
	"context"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestEmitSLOWithLastAnalysesNow(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tool := ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "codeql-codeql",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, &tool)
	repo1 := ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &repo1)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/main"),
		AnalysisComplete: true,
		ToolID:           1,
		MostRecent:       true,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		SourceRepositoryID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/develop"),
		AnalysisComplete: true,
		MostRecent:       true,
		ToolID:           1,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		SourceRepositoryID: 1,
	})
	s := &statter{
		Client: stats.NullStatter,
		s:      make(map[string]*tags),
	}
	ctx := appctx.WithStats(context.Background(), s)
	require.NoError(t, emitSLOs(ctx, db, tool, 8, 1))
	tag := s.s["code_scanning.managed_analyses.weekly_run.slo"]
	require.Equal(t, "true", tag.tags["success"])
}

func TestEmitSLOWithLastAnalysesAWeekAgo(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tool := ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "codeql-codeql",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, &tool)
	repo1 := ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &repo1)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/main"),
		AnalysisComplete: true,
		ToolID:           1,
		MostRecent:       true,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-7 * 24 * time.Hour),
			},
			CreatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-7 * 24 * time.Hour),
			},
		},
		SourceRepositoryID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/develop"),
		AnalysisComplete: true,
		MostRecent:       true,
		ToolID:           1,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-7 * 24 * time.Hour),
			},
			CreatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-7 * 24 * time.Hour),
			},
		},
		SourceRepositoryID: 1,
	})
	s := &statter{
		Client: stats.NullStatter,
		s:      make(map[string]*tags),
	}
	ctx := appctx.WithStats(context.Background(), s)
	require.NoError(t, emitSLOs(ctx, db, tool, 8, 1))
	tag := s.s["code_scanning.managed_analyses.weekly_run.slo"]
	require.Equal(t, "true", tag.tags["success"])
}

func TestEmitSLOWithLastAnalysesOverAWeekAgo(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tool := ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "codeql-codeql",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, &tool)
	repo1 := ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &repo1)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/main"),
		AnalysisComplete: true,
		ToolID:           1,
		MostRecent:       true,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
			CreatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
		},
		SourceRepositoryID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/develop"),
		AnalysisComplete: true,
		MostRecent:       true,
		ToolID:           1,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
			CreatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
		},
		SourceRepositoryID: 1,
	})
	s := &statter{
		Client: stats.NullStatter,
		s:      make(map[string]*tags),
	}
	ctx := appctx.WithStats(context.Background(), s)
	require.NoError(t, emitSLOs(ctx, db, tool, 8, 1))
	tag := s.s["code_scanning.managed_analyses.weekly_run.slo"]
	require.Equal(t, "false", tag.tags["success"])
}

func TestEmitSLOWithLastAnalysesOverAWeekAgoOnDefaultBranch(t *testing.T) {
	db := dbtest.RequireConnection(t)
	tool := ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "codeql-codeql",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, &tool)
	repo1 := ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &repo1)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/main"),
		AnalysisComplete: true,
		ToolID:           1,
		MostRecent:       true,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
			CreatedAt: sqltime.Time{
				Time: sqltime.Now().Add(-9 * 24 * time.Hour),
			},
		},
		SourceRepositoryID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/develop"),
		AnalysisComplete: true,
		MostRecent:       true,
		ToolID:           1,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		SourceRepositoryID: 1,
	})
	s := &statter{
		Client: stats.NullStatter,
		s:      make(map[string]*tags),
	}
	ctx := appctx.WithStats(context.Background(), s)
	require.NoError(t, emitSLOs(ctx, db, tool, 8, 1))
	tag := s.s["code_scanning.managed_analyses.weekly_run.slo"]
	require.Equal(t, "false", tag.tags["success"])
}

func TestRun(t *testing.T) {

	db := dbtest.RequireConnection(t)
	tool := ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "codeql-codeql",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, &tool)
	repo1 := ts.Repository{
		RepositoryID:        1,
		OwnerID:             2,
		SourceUpdatedAt:     sqltime.Now(),
		CodeScanningEnabled: true,
		DefaultRef:          []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &repo1)
	configID := ts.CodeqlConfigID(1)
	codeqlRepo := ts.CodeqlRepo{
		RepositoryID:    1,
		CurrentConfigID: &configID,
	}
	dbtest.RequireCreate(t, db, &codeqlRepo)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/main"),
		AnalysisComplete: true,
		ToolID:           1,
		MostRecent:       true,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		SourceRepositoryID: 1,
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		RepositoryID:     1,
		Ref:              []byte("refs/heads/develop"),
		AnalysisComplete: true,
		MostRecent:       true,
		ToolID:           1,
		BaseModel: ts.BaseModel{
			UpdatedAt: sqltime.Now(),
			CreatedAt: sqltime.Now(),
		},
		SourceRepositoryID: 1,
	})
	s := &statter{
		Client: stats.NullStatter,
		s:      make(map[string]*tags),
	}

	ctx := appctx.WithStats(context.Background(), s)
	cfg, err := config.Load()
	require.NoError(t, err)

	require.NoError(t, run(ctx, cfg, db, 8, 5000))
	tag, ok := s.s["code_scanning.managed_analyses.weekly_run.slo"]
	require.True(t, ok)
	require.Equal(t, "true", tag.tags["success"])
}

type tags struct {
	tags  stats.Tags
	value int64
}

type statter struct {
	stats.Client
	s map[string]*tags
}

func (s *statter) Counter(key string, t stats.Tags, value int64) {
	ta, ok := s.s[key]
	if !ok {
		s.s[key] = &tags{
			tags:  t,
			value: value,
		}
		return
	}
	for k, v := range t {
		s.s[key].tags[k] = v
	}
	ta.value += value
}
