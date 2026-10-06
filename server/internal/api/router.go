package api

import (
	"github.com/file4base/file4base-app/server/internal/auth"
	"github.com/file4base/file4base-app/server/internal/dbal"
	"github.com/go-chi/chi/v5"
)

// Options configures the API routes.
type Options struct {
	// AllowPublicDatabaseCreation lets callers without a session create new
	// databases. See SolutionHandlerOptions.
	AllowPublicDatabaseCreation bool
}

// Mount registers every domain route of the API on r.
//
// Routes fall into two groups:
//   - public: sign-in and the database selector used before sign-in;
//   - protected: everything else, which requires a valid session and always
//     runs against the database that session signed in to.
func Mount(r chi.Router, dbMgr *dbal.MultiDatabaseManager, sessions *auth.Store, opts Options) {
	authMW := NewAuthMiddleware(sessions, dbMgr)

	schemaHandler := NewSchemaHandler()
	dataHandler := NewDataHandler()
	securityHandler := NewSecurityHandler(dbMgr, sessions)
	solutionHandler := NewSolutionHandler(dbMgr, sessions, SolutionHandlerOptions{
		AllowPublicDatabaseCreation: opts.AllowPublicDatabaseCreation,
	})

	r.Group(func(r chi.Router) {
		r.Use(authMW.Optional)
		securityHandler.RegisterPublicRoutes(r)
		solutionHandler.RegisterPublicRoutes(r)
	})

	r.Group(func(r chi.Router) {
		r.Use(authMW.Authenticate)
		schemaHandler.RegisterRoutes(r)
		dataHandler.RegisterRoutes(r)
		securityHandler.RegisterRoutes(r)
		solutionHandler.RegisterRoutes(r)
	})
}
