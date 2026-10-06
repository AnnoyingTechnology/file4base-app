package dbal_test

import (
	"context"
	"testing"

	"github.com/file4base/file4base-app/server/internal/dbal"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMultiDatabaseManager_BuildDSN(t *testing.T) {
	mgr, err := dbal.NewMultiDatabaseManager(dbal.EnginePostgres, "postgres://file4base:dev_password@localhost:5432/file4base_dev?sslmode=disable")
	require.NoError(t, err)

	assert.Equal(t, "file4base_dev", mgr.DefaultDatabase())

	dsnNew := mgr.BuildDSN("invoices_db")
	assert.Equal(t, "postgres://file4base:dev_password@localhost:5432/invoices_db?sslmode=disable", dsnNew)
}

func TestMultiDatabaseManager_InvalidNames(t *testing.T) {
	mgr, err := dbal.NewMultiDatabaseManager(dbal.EnginePostgres, "postgres://file4base:dev_password@localhost:5432/file4base_dev?sslmode=disable")
	require.NoError(t, err)

	ctx := context.Background()

	// Invalid characters or injection attempts should be rejected
	err = mgr.CreateDatabase(ctx, "invoices; DROP DATABASE file4base_dev;")
	assert.Error(t, err)

	_, err = mgr.DriverFor(ctx, "123invalid")
	assert.Error(t, err)
}

func TestMultiDatabaseManager_ProtectedDatabases(t *testing.T) {
	mgr, err := dbal.NewMultiDatabaseManager(dbal.EnginePostgres, "postgres://file4base:dev_password@localhost:5432/postgres?sslmode=disable")
	require.NoError(t, err)

	ctx := context.Background()

	for _, name := range []string{"postgres", "template1", "mysql", "information_schema", "Postgres"} {
		assert.True(t, dbal.IsProtectedDatabase(name), name)

		// Engine-internal databases can never back a session, be created or be dropped.
		// These checks happen before any connection is attempted.
		_, err := mgr.DriverFor(ctx, name)
		assert.Error(t, err, name)
		assert.Error(t, mgr.CreateDatabase(ctx, name), name)
		assert.Error(t, mgr.DropDatabase(ctx, name), name)
	}

	assert.False(t, dbal.IsProtectedDatabase("invoices_db"))
	assert.True(t, dbal.IsValidDatabaseName("invoices_db"))
	assert.False(t, dbal.IsValidDatabaseName("invoices-db"))
}

func TestDriverContext(t *testing.T) {
	_, ok := dbal.DriverFromContext(context.Background())
	assert.False(t, ok)

	driver := dbal.NewGenericDriver(nil, nil)
	got, ok := dbal.DriverFromContext(dbal.WithDriver(context.Background(), driver))
	require.True(t, ok)
	assert.Equal(t, driver, got)
}
