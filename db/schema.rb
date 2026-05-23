# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_23_180000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "application_mailboxes", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at"
    t.string "provider", default: "google", null: false
    t.text "refresh_token"
    t.text "scopes"
    t.datetime "updated_at", null: false
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id"
    t.datetime "created_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.bigint "tenant_id", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
    t.index ["tenant_id"], name: "index_audit_logs_on_tenant_id"
  end

  create_table "campaign_instances", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "campaign_revision_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.bigint "host_id", null: false
    t.string "host_type", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_instances_on_campaign_id"
    t.index ["campaign_revision_id"], name: "index_campaign_instances_on_campaign_revision_id"
    t.index ["host_type", "host_id"], name: "index_campaign_instances_on_host"
  end

  create_table "campaign_revisions", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_user_id"
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.integer "revision_number", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_campaign_revisions_on_approved_by_user_id"
    t.index ["campaign_id", "revision_number"], name: "index_campaign_revisions_on_campaign_id_and_revision_number", unique: true
    t.index ["campaign_id"], name: "index_campaign_revisions_on_campaign_id"
    t.index ["campaign_id"], name: "index_campaign_revisions_one_active_per_campaign", unique: true, where: "(status = 1)"
    t.index ["created_by_user_id"], name: "index_campaign_revisions_on_created_by_user_id"
  end

  create_table "campaign_step_instances", force: :cascade do |t|
    t.bigint "campaign_instance_id", null: false
    t.bigint "campaign_step_id", null: false
    t.datetime "created_at", null: false
    t.boolean "customer_replied", default: false, null: false
    t.integer "email_delivery_status", default: 0, null: false
    t.text "final_body"
    t.string "final_subject"
    t.jsonb "gmail_reply_payload"
    t.jsonb "gmail_send_response"
    t.string "gmail_thread_id"
    t.jsonb "gmail_thread_snapshot"
    t.datetime "planned_delivery_at"
    t.datetime "updated_at", null: false
    t.index ["campaign_instance_id"], name: "index_campaign_step_instances_on_campaign_instance_id"
    t.index ["campaign_step_id"], name: "index_campaign_step_instances_on_campaign_step_id"
  end

  create_table "campaign_steps", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "campaign_revision_id", null: false
    t.datetime "created_at", null: false
    t.integer "offset_min", null: false
    t.integer "sequence_number", null: false
    t.text "template_body"
    t.string "template_subject"
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_campaign_steps_on_campaign_id"
    t.index ["campaign_revision_id", "sequence_number"], name: "index_campaign_steps_on_revision_and_sequence", unique: true
    t.index ["campaign_revision_id"], name: "index_campaign_steps_on_campaign_revision_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_user_id"
    t.bigint "attributed_to_id"
    t.string "attributed_to_type"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "name", null: false
    t.datetime "paused_at"
    t.bigint "paused_by_user_id"
    t.integer "status", default: 0, null: false
    t.string "template_version_id"
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_campaigns_on_approved_by_user_id"
    t.index ["attributed_to_type", "attributed_to_id"], name: "index_campaigns_on_attributed_to"
    t.index ["discarded_at"], name: "index_campaigns_on_discarded_at"
    t.index ["paused_by_user_id"], name: "index_campaigns_on_paused_by_user_id"
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "model_id"
    t.datetime "updated_at", null: false
    t.index ["model_id"], name: "index_chats_on_model_id"
  end

  create_table "email_delegations", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at"
    t.string "provider", default: "google", null: false
    t.text "refresh_token"
    t.text "scopes"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "provider", "email"], name: "index_email_delegations_on_user_id_and_provider_and_email", unique: true
    t.index ["user_id"], name: "index_email_delegations_on_user_id"
  end

  create_table "email_suppressions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "location_id", null: false
    t.text "notes"
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "email"], name: "index_email_suppressions_on_location_id_and_email", unique: true
    t.index ["location_id"], name: "index_email_suppressions_on_location_id"
  end

  create_table "integration_checks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.text "error_message"
    t.string "key", null: false
    t.datetime "last_checked_at"
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_integration_checks_on_key", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "first_name"
    t.bigint "invited_by_user_id", null: false
    t.string "last_name"
    t.bigint "location_id"
    t.string "phone_number"
    t.bigint "tenant_id", null: false
    t.string "title"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_user_id"], name: "index_invitations_on_invited_by_user_id"
    t.index ["location_id"], name: "index_invitations_on_location_id"
    t.index ["tenant_id"], name: "index_invitations_on_tenant_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "job_proposal_attachments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_proposal_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_user_id"
    t.index ["job_proposal_id"], name: "index_job_proposal_attachments_on_job_proposal_id"
    t.index ["uploaded_by_user_id"], name: "index_job_proposal_attachments_on_uploaded_by_user_id"
  end

  create_table "job_proposals", force: :cascade do |t|
    t.datetime "closed_at"
    t.bigint "closed_by_user_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.string "customer_city"
    t.string "customer_email"
    t.string "customer_first_name"
    t.string "customer_house_number"
    t.string "customer_last_name"
    t.string "customer_state"
    t.string "customer_street"
    t.string "customer_title"
    t.string "customer_zip"
    t.string "dash_job_number"
    t.datetime "discarded_at"
    t.string "internal_reference"
    t.text "job_description"
    t.bigint "job_type_id"
    t.jsonb "last_reply"
    t.bigint "location_id", null: false
    t.text "loss_notes"
    t.bigint "loss_reason_id"
    t.bigint "owner_id", null: false
    t.string "pipeline_stage"
    t.decimal "proposal_value", precision: 12, scale: 2
    t.bigint "scenario_id"
    t.integer "status", default: 0, null: false
    t.string "status_details"
    t.string "status_overlay"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["closed_by_user_id"], name: "index_job_proposals_on_closed_by_user_id"
    t.index ["created_by_user_id"], name: "index_job_proposals_on_created_by_user_id"
    t.index ["dash_job_number"], name: "index_job_proposals_on_dash_job_number"
    t.index ["discarded_at"], name: "index_job_proposals_on_discarded_at"
    t.index ["job_type_id"], name: "index_job_proposals_on_job_type_id"
    t.index ["location_id"], name: "index_job_proposals_on_location_id"
    t.index ["loss_reason_id"], name: "index_job_proposals_on_loss_reason_id"
    t.index ["owner_id"], name: "index_job_proposals_on_owner_id"
    t.index ["scenario_id"], name: "index_job_proposals_on_scenario_id"
    t.index ["tenant_id"], name: "index_job_proposals_on_tenant_id"
  end

  create_table "job_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "type_code", limit: 64
    t.datetime "updated_at", null: false
    t.index ["type_code"], name: "index_job_types_on_type_code", unique: true
  end

  create_table "locations", force: :cascade do |t|
    t.string "address_line_1", null: false
    t.string "address_line_2"
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.string "display_name", null: false
    t.boolean "is_active", default: false, null: false
    t.string "phone_number", null: false
    t.string "postal_code", null: false
    t.string "state", limit: 2, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_user_id"
    t.index ["created_by_user_id"], name: "index_locations_on_created_by_user_id"
    t.index ["is_active"], name: "index_locations_on_is_active"
    t.index ["tenant_id"], name: "index_locations_on_tenant_id"
    t.index ["updated_by_user_id"], name: "index_locations_on_updated_by_user_id"
  end

  create_table "loss_reasons", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_loss_reasons_on_code", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.bigint "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.bigint "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.bigint "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.jsonb "metadata", default: {}
    t.jsonb "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "pdf_processing_revisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "instructions", null: false
    t.bigint "model_id", null: false
    t.integer "revision_number", null: false
    t.datetime "updated_at", null: false
    t.index ["model_id"], name: "index_pdf_processing_revisions_on_model_id"
    t.index ["revision_number"], name: "index_pdf_processing_revisions_on_revision_number", unique: true
  end

  create_table "scenarios", force: :cascade do |t|
    t.bigint "campaign_id"
    t.string "code", limit: 64, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "industry_classification"
    t.bigint "job_type_id", null: false
    t.string "short_name", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_scenarios_on_campaign_id"
    t.index ["job_type_id", "code"], name: "index_scenarios_on_job_type_id_and_code", unique: true
    t.index ["job_type_id"], name: "index_scenarios_on_job_type_id"
  end

  create_table "tenant_job_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: false, null: false
    t.bigint "job_type_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["job_type_id"], name: "index_tenant_job_types_on_job_type_id"
    t.index ["tenant_id", "job_type_id"], name: "index_tenant_job_types_on_tenant_id_and_job_type_id", unique: true
    t.index ["tenant_id"], name: "index_tenant_job_types_on_tenant_id"
  end

  create_table "tenant_scenarios", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: false, null: false
    t.bigint "scenario_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["scenario_id"], name: "index_tenant_scenarios_on_scenario_id"
    t.index ["tenant_id", "scenario_id"], name: "index_tenant_scenarios_on_tenant_id_and_scenario_id", unique: true
    t.index ["tenant_id"], name: "index_tenant_scenarios_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "company_name"
    t.datetime "created_at", null: false
    t.boolean "job_reference_required", default: false, null: false
    t.string "logo_url"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tool_calls", force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.datetime "discarded_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.boolean "is_admin", default: false, null: false
    t.boolean "is_pending", default: true, null: false
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.bigint "location_id"
    t.string "phone_number"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.bigint "tenant_id"
    t.string "time_zone", default: "Central Time (US & Canada)", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["discarded_at"], name: "index_users_on_discarded_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["location_id"], name: "index_users_on_location_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_logs", "tenants"
  add_foreign_key "audit_logs", "users", column: "actor_user_id"
  add_foreign_key "campaign_instances", "campaign_revisions"
  add_foreign_key "campaign_instances", "campaigns"
  add_foreign_key "campaign_revisions", "campaigns"
  add_foreign_key "campaign_revisions", "users", column: "approved_by_user_id"
  add_foreign_key "campaign_revisions", "users", column: "created_by_user_id"
  add_foreign_key "campaign_step_instances", "campaign_instances"
  add_foreign_key "campaign_step_instances", "campaign_steps"
  add_foreign_key "campaign_steps", "campaign_revisions"
  add_foreign_key "campaign_steps", "campaigns"
  add_foreign_key "campaigns", "users", column: "approved_by_user_id"
  add_foreign_key "campaigns", "users", column: "paused_by_user_id"
  add_foreign_key "chats", "models"
  add_foreign_key "email_delegations", "users"
  add_foreign_key "email_suppressions", "locations"
  add_foreign_key "invitations", "locations"
  add_foreign_key "invitations", "tenants"
  add_foreign_key "invitations", "users", column: "invited_by_user_id"
  add_foreign_key "job_proposal_attachments", "job_proposals"
  add_foreign_key "job_proposal_attachments", "users", column: "uploaded_by_user_id"
  add_foreign_key "job_proposals", "job_types"
  add_foreign_key "job_proposals", "locations"
  add_foreign_key "job_proposals", "loss_reasons"
  add_foreign_key "job_proposals", "scenarios"
  add_foreign_key "job_proposals", "tenants"
  add_foreign_key "job_proposals", "users", column: "closed_by_user_id"
  add_foreign_key "job_proposals", "users", column: "created_by_user_id"
  add_foreign_key "job_proposals", "users", column: "owner_id"
  add_foreign_key "locations", "tenants"
  add_foreign_key "locations", "users", column: "created_by_user_id"
  add_foreign_key "locations", "users", column: "updated_by_user_id"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "pdf_processing_revisions", "models"
  add_foreign_key "scenarios", "campaigns"
  add_foreign_key "scenarios", "job_types"
  add_foreign_key "tenant_job_types", "job_types"
  add_foreign_key "tenant_job_types", "tenants"
  add_foreign_key "tenant_scenarios", "scenarios"
  add_foreign_key "tenant_scenarios", "tenants"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "users", "locations"
  add_foreign_key "users", "tenants"
end
