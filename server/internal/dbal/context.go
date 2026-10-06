package dbal

import "context"

type driverContextKey struct{}

// WithDriver returns a context carrying the DatabaseDriver that the current
// request must operate on. The API layer resolves it from the caller's
// session, so two clients working on different databases never share state.
func WithDriver(ctx context.Context, driver DatabaseDriver) context.Context {
	return context.WithValue(ctx, driverContextKey{}, driver)
}

// DriverFromContext returns the request-scoped DatabaseDriver, if any.
func DriverFromContext(ctx context.Context) (DatabaseDriver, bool) {
	driver, ok := ctx.Value(driverContextKey{}).(DatabaseDriver)
	return driver, ok && driver != nil
}
