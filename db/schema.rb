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

ActiveRecord::Schema[8.1].define(version: 2026_03_15_211217) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "events", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "curated_category"
    t.string "curated_date_text"
    t.string "curated_event_url"
    t.string "curated_name"
    t.string "curated_venue"
    t.string "date_text"
    t.text "description"
    t.string "event_url"
    t.boolean "featured", default: false, null: false
    t.string "first_seen"
    t.string "image_url"
    t.string "last_seen"
    t.string "name", null: false
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.bigint "source_id"
    t.date "start_date"
    t.string "status", default: "pending", null: false
    t.integer "times_listed", default: 1
    t.datetime "updated_at", null: false
    t.string "venue"
    t.bigint "venue_id"
    t.string "venue_room"
    t.string "zone", default: "coventry", null: false
    t.index ["category"], name: "index_events_on_category"
    t.index ["name", "venue"], name: "index_events_on_name_and_venue", unique: true
    t.index ["name"], name: "index_events_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["source_id"], name: "index_events_on_source_id"
    t.index ["status"], name: "index_events_on_status"
    t.index ["venue"], name: "index_events_on_venue", opclass: :gin_trgm_ops, using: :gin
    t.index ["venue_id"], name: "index_events_on_venue_id"
    t.index ["zone"], name: "index_events_on_zone"
  end

  create_table "feeds", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "default_category"
    t.string "feed_type", default: "web", null: false
    t.integer "fetch_interval_hours", default: 24, null: false
    t.datetime "last_fetched_at"
    t.text "last_run_error"
    t.string "last_run_status", default: "idle"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["active"], name: "index_feeds_on_active"
    t.index ["feed_type"], name: "index_feeds_on_feed_type"
    t.index ["url"], name: "index_feeds_on_url", unique: true
  end

  create_table "import_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "last_run_at"
    t.text "last_run_error"
    t.string "status", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_import_statuses_on_key", unique: true
  end

  create_table "sources", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.string "date_range"
    t.datetime "published_at"
    t.string "source_type", default: "reddit", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "week_number"
    t.index ["archived"], name: "index_sources_on_archived"
    t.index ["source_type"], name: "index_sources_on_source_type"
    t.index ["url"], name: "index_sources_on_url", unique: true
    t.index ["week_number"], name: "index_sources_on_week_number"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "venues", force: :cascade do |t|
    t.string "address"
    t.text "aliases", default: [], array: true
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "zone", default: "coventry", null: false
    t.index ["name"], name: "index_venues_on_name", opclass: :gin_trgm_ops, using: :gin
  end

  add_foreign_key "events", "sources"
  add_foreign_key "events", "venues"
end
