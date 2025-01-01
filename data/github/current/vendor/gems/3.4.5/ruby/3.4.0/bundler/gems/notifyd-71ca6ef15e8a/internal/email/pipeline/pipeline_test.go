package pipeline

import (
	"context"
	"testing"

	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/stretchr/testify/require"
)

func Test_Minifier(t *testing.T) {
	ctx := context.Background()
	minifer := NewMinifier()

	fixture := `
		<body>
			<p style="color: red">This has some white spaces</p>

			<p>It shouldn't</p>
		</body>
	`

	expected := `<body><p style="color: red">This has some white spaces</p><p>It shouldn't</p></body>`

	actual, err := minifer.Process(ctx, tenancy.NewSingleTenant(), fixture)
	require.NoError(t, err)

	require.Equal(t, expected, actual)
}
