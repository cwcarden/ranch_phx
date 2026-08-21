defmodule RanchPhxWeb.UserSessionHTML do
  use RanchPhxWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:ranch_phx, RanchPhx.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
