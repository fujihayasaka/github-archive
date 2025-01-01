package devicetokens

import (
	"context"
	"fmt"
	"sort"
	"testing"

	"github.com/Masterminds/squirrel"
	"github.com/benbjohnson/clock"
	_ "github.com/go-sql-driver/mysql"
	"github.com/stretchr/testify/require"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func TestDatabaseAccess(t *testing.T) {
	ctx := context.Background()
	r := require.New(t)
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	defer dbCleanup()

	t.Run("with OauthAccessId", func(t *testing.T) {
		tables := []string{"mobile_device_tokens"}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		insert(t, db, Token{
			UserID:        123,
			DeviceToken:   "abc123",
			OauthAccessID: 1,
		})
		token := getOne(ctx, t, storage, 123)

		r.Equal("abc123", token.DeviceToken)
		r.Equal(int64(1), token.OauthAccessID)
	})

	t.Run("without OauthAccessId", func(t *testing.T) {
		tables := []string{"mobile_device_tokens"}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		insert(t, db, Token{
			UserID:      124,
			DeviceToken: "abc123",
		})
		token := getOne(ctx, t, storage, 124)

		r.Equal("abc123", token.DeviceToken)
		r.Zero(token.OauthAccessID)
	})
}

func TestSet_Insert(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)
	deviceToken := "a token"

	tcs := []struct {
		name          string
		oauthAccessID int64
	}{
		{
			name:          "With OauthAccessID",
			oauthAccessID: 1,
		},
		{
			name:          "Without OauthAccessID",
			oauthAccessID: 0,
		},
	}

	for _, tc := range tcs {
		t.Run(tc.name, func(t *testing.T) {
			tables := []string{"mobile_device_tokens"}
			if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
				panic(fmt.Sprintf("truncate test db: %s", err))
			}

			storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)

			set, err := storage.Set(ctx, userID, tc.oauthAccessID, deviceToken)
			r.NoError(err)
			r.True(set)
			token := getOne(ctx, t, storage, userID)
			r.Equal(token.UserID, userID)
			r.Equal(token.DeviceToken, deviceToken)
			r.Equal(token.OauthAccessID, tc.oauthAccessID)
		})
	}
}

func TestSet_InsertOverLimit(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)
	deviceToken := "a token"

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	tokens := make([]Token, maxTokensPerUser)
	for i := range maxTokensPerUser {
		tokens[i] = Token{
			UserID:        userID,
			DeviceToken:   fmt.Sprintf("%s#%d", deviceToken, i),
			OauthAccessID: int64(i + 1),
		}
	}
	insert(t, db, tokens...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	set, err := storage.Set(ctx, userID, 42, "new token")
	r.NoError(err)
	r.False(set)
}

func TestSet_Update(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)
	deviceToken := "a token"

	tcs := []struct {
		name          string
		oauthAccessID int64
	}{
		{
			name:          "With OauthAccessID",
			oauthAccessID: 1,
		},
		{
			name:          "Without OauthAccessID",
			oauthAccessID: 0,
		},
	}

	for _, tc := range tcs {
		t.Run(tc.name, func(t *testing.T) {
			tables := []string{"mobile_device_tokens"}
			if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
				panic(fmt.Sprintf("truncate test db: %s", err))
			}

			insert(t, db, Token{
				UserID:        userID,
				DeviceToken:   deviceToken,
				OauthAccessID: tc.oauthAccessID + 1,
			})

			storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
			set, err := storage.Set(ctx, userID, tc.oauthAccessID, deviceToken)
			r.NoError(err)
			r.True(set)
			token := getOne(ctx, t, storage, userID)
			r.Equal(token.UserID, userID)
			r.Equal(token.DeviceToken, deviceToken)
			r.Equal(token.OauthAccessID, tc.oauthAccessID)
		})
	}
}

func TestSet_UpdateOverLimit(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)
	deviceToken := "a token"

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	tokens := make([]Token, maxTokensPerUser)
	for i := range maxTokensPerUser {
		tokens[i] = Token{
			UserID:        userID,
			DeviceToken:   fmt.Sprintf("%s#%d", deviceToken, i),
			OauthAccessID: int64(i + 1),
		}
	}
	insert(t, db, tokens...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	for i := range maxTokensPerUser {
		deviceToken := fmt.Sprintf("%s#%d", deviceToken, i)
		set, err := storage.Set(ctx, userID, int64(100+i), deviceToken)
		r.NoError(err)
		r.True(set)
	}

	tokens, err := storage.Get(context.Background(), userID)
	r.NoError(err)
	r.Len(tokens, maxTokensPerUser)
	sort.Slice(tokens, func(i, j int) bool { return tokens[i].OauthAccessID < tokens[j].OauthAccessID })
	for i, token := range tokens {
		r.Equal(token.DeviceToken, fmt.Sprintf("%s#%d", deviceToken, i))
		r.Equal(token.OauthAccessID, int64(100+i))
	}
}

func TestDelete(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	insert(t, db, Tokens{Token{
		UserID:      userID,
		DeviceToken: "a token",
	}, Token{
		UserID:      userID,
		DeviceToken: "another-token",
	}}...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	r.NoError(storage.Delete(ctx, userID, "a token"))
	tokens, err := storage.Get(ctx, userID)
	r.NoError(err)
	r.Len(tokens, 1)
	r.Equal("another-token", tokens[0].DeviceToken)
}

func TestDelete_None(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	insert(t, db, Tokens{Token{
		UserID:      userID,
		DeviceToken: "a token",
	}, Token{
		UserID:      userID,
		DeviceToken: "another-token",
	}}...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	r.NoError(storage.Delete(ctx, userID))
	tokens, err := storage.Get(ctx, userID)
	r.NoError(err)
	r.Len(tokens, 2)
}

func TestDelete_Multiple(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	insert(t, db, Tokens{Token{
		UserID:      userID,
		DeviceToken: "a token",
	}, Token{
		UserID:      userID,
		DeviceToken: "another-token",
	}, Token{
		UserID:      userID,
		DeviceToken: "yet-another-token",
	}}...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	r.NoError(storage.Delete(ctx, userID, "a token", "yet-another-token"))
	tokens, err := storage.Get(ctx, userID)
	r.NoError(err)
	r.Len(tokens, 1)
	r.Equal("another-token", tokens[0].DeviceToken)
}

func TestDelete_NotFound(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	insert(t, db, Tokens{Token{
		UserID:      userID,
		DeviceToken: "a token",
	}, Token{
		UserID:      userID,
		DeviceToken: "another-token",
	}}...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	r.NoError(storage.Delete(ctx, userID, "non-existent token"))
	tokens, err := storage.Get(ctx, userID)
	r.NoError(err)
	r.Len(tokens, 2)
}

func TestDeleteAll(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()

	userID := int64(1)

	tables := []string{"mobile_device_tokens"}
	if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	insert(t, db, Tokens{Token{
		UserID:      userID,
		DeviceToken: "a token",
	}, Token{
		UserID:      userID,
		DeviceToken: "another-token",
	}, Token{
		UserID:      userID + 1,
		DeviceToken: "a token",
	}}...)

	storage := NewStorage(clock.NewMock(), logs.NullTelem, stats.NullStatter, db)
	r.NoError(storage.DeleteAll(ctx, userID))
	tokens, err := storage.Get(ctx, userID)
	r.NoError(err)
	r.Empty(tokens)
	tokens, err = storage.Get(ctx, userID+1)
	r.NoError(err)
	r.Len(tokens, 1)
}

func insert(t *testing.T, db mysql.DB, tokens ...Token) {
	t.Helper()
	r := require.New(t)

	ts := mysql.NewTimestamps(clock.NewMock())
	insert := squirrel.Insert("mobile_device_tokens").
		Columns("user_id", "device_token", "oauth_access_id", "created_at", "updated_at")
	for _, token := range tokens {
		insert = insert.Values(
			token.UserID,
			token.DeviceToken,
			token.OauthAccessID,
			ts.CreatedAt,
			ts.UpdatedAt,
		)
	}
	_, err := insert.RunWith(db.Write).Exec()
	r.NoError(err)
}

func getOne(ctx context.Context, t *testing.T, s Storage, userID int64) Token {
	t.Helper()
	r := require.New(t)

	tokens, err := s.Get(ctx, userID)
	r.NoError(err)
	r.Len(tokens, 1)
	return tokens[0]
}
