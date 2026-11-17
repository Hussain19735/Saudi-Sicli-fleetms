defmodule Fleetms.Integrations.SharePoint.ServiceTest do
  use ExUnit.Case, async: true

  alias Fleetms.Integrations.SharePoint.Service

  test "denies create before contacting SharePoint when scope is missing" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{"Title" => "Test"}, %{})
  end

  test "denies create when target project is outside the actor scope" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}
    target = %{project_id: "P-2", city_id: "JED"}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{"Title" => "Test"}, target)
  end

  test "denies update when existing record scope is outside actor scope" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}
    existing_scope = %{project_id: "P-2", city_id: "JED"}

    assert {:error, :forbidden} =
             Service.update(
               %{},
               actor,
               :breakdown_reports,
               "42",
               %{"Title" => "Changed"},
               nil,
               existing_scope
             )
  end

  test "denies list when scope is absent" do
    actor = %{role: :maintenance_team, project_ids: ["P-1"], city_ids: ["JED"]}

    assert {:error, :forbidden} =
             Service.list(%{}, actor, :vehicles, [], %{})
  end

  test "company admin is authorized for an in-scope operation" do
    assert :ok =
             Service.authorize(%{role: :company_admin}, :update, %{
               project_id: "P-1",
               city_id: "JED"
             })
  end

  test "employee cannot use maintenance operations" do
    actor = %{role: :employee, vehicle_ids: ["V-1"]}

    assert {:error, :forbidden} =
             Service.create(%{}, actor, :breakdown_reports, %{}, %{vehicle_id: "V-1"})
  end
end
