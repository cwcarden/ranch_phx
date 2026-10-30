import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ranch_phx, RanchPhx.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ranch_phx_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ranch_phx, RanchPhxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "OCGvFfiF+mpmTh2c5J0wAefwmGzjs5NJ1TozgcOXeerlCjKrbAY7p4mh3ynw2ghO",
  server: false

# Use test adapter for Swoosh so no emails are actually sent during tests
config :ranch_phx, RanchPhx.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Swoosh test adapter needs no HTTP client
config :swoosh, :api_client, false

# The Coach calls a stub instead of the Claude API in tests.
config :ranch_phx, :anthropic_api_key, "test-key"
config :ranch_phx, :coach_req_options, plug: {Req.Test, RanchPhx.Training.Coach}, retry: false

# Phone notifications: no reminder timer in tests; pushes go to a stub.
config :ranch_phx, :push_reminders, false
config :ranch_phx, :voice_push, false
config :ranch_phx, :push_req_options, plug: {Req.Test, RanchPhx.Push}

# Off-site backup: no nightly runs in tests; R2 calls go to a stub.
config :ranch_phx, :nightly_backup, false
config :ranch_phx, :backup_req_options, plug: {Req.Test, RanchPhx.Backup.R2}, retry: false
