package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/file4base/file4base-app/server/internal/api"
	"github.com/file4base/file4base-app/server/internal/dbal"
	"github.com/file4base/file4base-app/server/internal/schema"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupSecurityRouter(t *testing.T) (*chi.Mux, *dbal.MultiDatabaseManager) {
	dsn := "postgres://file4base:dev_password@localhost:5432/file4base_dev?sslmode=disable"
	mgr, err := dbal.NewMultiDatabaseManager(dbal.EnginePostgres, dsn)
	if err != nil {
		t.Skip("PostgreSQL multi-db not available:", err)
		return nil, nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := mgr.Ping(ctx); err != nil {
		t.Skip("PostgreSQL ping failed:", err)
		return nil, nil
	}

	schemaSvc := schema.NewService(mgr)
	require.NoError(t, schemaSvc.EnsureSystemTables(ctx))

	r := chi.NewRouter()
	handler := api.NewSecurityHandler(mgr, schemaSvc)
	handler.RegisterRoutes(r)

	return r, mgr
}

func TestSecurityHandler_ListAndCreateUsers(t *testing.T) {
	r, _ := setupSecurityRouter(t)
	if r == nil {
		return
	}

	// 1. List users on active DB
	req, _ := http.NewRequest(http.MethodGet, "/api/v1/security/users", nil)
	rr := httptest.NewRecorder()
	r.ServeHTTP(rr, req)
	assert.Equal(t, http.StatusOK, rr.Code)

	var users []schema.UserMetadata
	err := json.NewDecoder(rr.Body).Decode(&users)
	require.NoError(t, err)
	assert.NotEmpty(t, users)

	// 2. Create a test user scoped with database parameter
	userPayload := map[string]interface{}{
		"username": "scoped_test_user",
		"password": "Password123!",
		"role":     "user",
	}
	bodyBytes, _ := json.Marshal(userPayload)
	postReq, _ := http.NewRequest(http.MethodPost, "/api/v1/security/users?database=file4base_dev", bytes.NewReader(bodyBytes))
	postReq.Header.Set("Content-Type", "application/json")
	postRR := httptest.NewRecorder()
	r.ServeHTTP(postRR, postReq)
	// Could be 201 Created or 400 if user already exists
	if postRR.Code == http.StatusCreated {
		var created schema.UserMetadata
		_ = json.NewDecoder(postRR.Body).Decode(&created)
		assert.Equal(t, "scoped_test_user", created.Username)

		// Clean up
		delReq, _ := http.NewRequest(http.MethodDelete, "/api/v1/security/users/"+created.ID+"?database=file4base_dev", nil)
		delRR := httptest.NewRecorder()
		r.ServeHTTP(delRR, delReq)
		assert.Equal(t, http.StatusNoContent, delRR.Code)
	}
}
