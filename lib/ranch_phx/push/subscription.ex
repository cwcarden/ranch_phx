defmodule RanchPhx.Push.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :device, :string
    belongs_to :user, RanchPhx.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:user_id, :endpoint, :p256dh, :auth, :device])
    |> validate_required([:user_id, :endpoint, :p256dh, :auth])
    |> validate_format(:endpoint, ~r{^https://})
    |> unique_constraint(:endpoint)
  end
end
