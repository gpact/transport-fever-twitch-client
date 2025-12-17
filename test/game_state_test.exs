defmodule TF2Client.GameStateTest do
  use ExUnit.Case, async: true

  alias TF2Client.GameState

  test "reads profit from players_income" do
    game_state = %{"players_income" => %{"alice" => 1200, "bob" => -50}}

    assert {:ok, 1200} = GameState.profit_for_username(game_state, "alice")
    assert {:ok, -50} = GameState.profit_for_username(game_state, "bob")
    assert {:ok, 1200} = GameState.profit_for_username(game_state, "ALICE")
  end

  test "computes profit from company yearly income/expenses when players_income is missing" do
    game_state = %{
      "companies" => %{
        "alice" => %{
          "yearlyIncome" => %{
            "1871" => %{"1" => 10, "2" => 20},
            "1872" => %{"1" => 15}
          },
          "yearlyExpenses" => %{
            "1871" => %{"1" => 7},
            "1872" => %{"1" => 9, "2" => 2}
          }
        }
      }
    }

    assert {:ok, 27} = GameState.profit_for_username(game_state, "alice")
  end

  test "counts vehicles owned from owned_vehicles" do
    game_state = %{"owned_vehicles" => %{"1" => "alice", "2" => "bob", "3" => "alice"}}

    assert {:ok, 2} = GameState.vehicles_owned_count(game_state, "alice")
    assert {:ok, 1} = GameState.vehicles_owned_count(game_state, "bob")
    assert {:ok, 2} = GameState.vehicles_owned_count(game_state, "ALICE")
  end

  test "counts vehicles owned from company vehicles when owned_vehicles is missing" do
    game_state = %{
      "companies" => %{
        "alice" => %{
          "vehicles" => %{
            "10" => %{"id" => 10},
            "11" => %{"id" => 11}
          }
        }
      }
    }

    assert {:ok, 2} = GameState.vehicles_owned_count(game_state, "alice")
  end

  test "ranks top players by profit" do
    game_state = %{
      "players_income" => %{
        "alice" => 100,
        "bob" => -50,
        "carol" => 200
      }
    }

    assert [{"carol", 200}, {"alice", 100}] = GameState.top_players_by_profit(game_state, 2)
  end

  test "detects one-time claim and town purchase" do
    game_state = %{
      "companies" => %{"Alice" => %{}},
      "owned_towns" => %{"1" => "alice"}
    }

    assert GameState.company_claimed?(game_state, "alice")
    assert GameState.town_purchased?(game_state, "alice")
    refute GameState.company_claimed?(game_state, "bob")
    refute GameState.town_purchased?(game_state, "bob")
  end
end
