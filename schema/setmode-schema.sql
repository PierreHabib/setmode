

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."journey_stage" AS ENUM (
    'discover',
    'connect',
    'activate',
    'integrate',
    'amplify',
    'advocate'
);


ALTER TYPE "public"."journey_stage" OWNER TO "postgres";


CREATE TYPE "public"."message_sender" AS ENUM (
    'user',
    'setmode'
);


ALTER TYPE "public"."message_sender" OWNER TO "postgres";


CREATE TYPE "public"."output_format_type" AS ENUM (
    'blog',
    'linkedin',
    'newsletter',
    'meta_description',
    'whatsapp',
    'plan',
    'summary',
    'html',
    'slug',
    'header'
);


ALTER TYPE "public"."output_format_type" OWNER TO "postgres";


CREATE TYPE "public"."persona_type" AS ENUM (
    'strategist',
    'creator',
    'connector'
);


ALTER TYPE "public"."persona_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_complete_schema"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result jsonb;
BEGIN
    -- Get all enums
    WITH enum_types AS (
        SELECT 
            t.typname as enum_name,
            array_agg(e.enumlabel ORDER BY e.enumsortorder) as enum_values
        FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public'
        GROUP BY t.typname
    )
    SELECT jsonb_build_object(
        'enums',
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'name', enum_name,
                    'values', to_jsonb(enum_values)
                )
            ),
            '[]'::jsonb
        )
    )
    FROM enum_types
    INTO result;

    -- Get all tables with their details
    WITH RECURSIVE 
    columns_info AS (
        SELECT 
            c.oid as table_oid,
            c.relname as table_name,
            a.attname as column_name,
            format_type(a.atttypid, a.atttypmod) as column_type,
            a.attnotnull as notnull,
            pg_get_expr(d.adbin, d.adrelid) as column_default,
            CASE 
                WHEN a.attidentity != '' THEN true
                WHEN pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval%' THEN true
                ELSE false
            END as is_identity,
            EXISTS (
                SELECT 1 FROM pg_constraint con 
                WHERE con.conrelid = c.oid 
                AND con.contype = 'p' 
                AND a.attnum = ANY(con.conkey)
            ) as is_pk
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute a ON a.attrelid = c.oid
        LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
        WHERE n.nspname = 'public' 
        AND c.relkind = 'r'
        AND a.attnum > 0 
        AND NOT a.attisdropped
    ),
    fk_info AS (
        SELECT 
            c.oid as table_oid,
            jsonb_agg(
                jsonb_build_object(
                    'name', con.conname,
                    'column', col.attname,
                    'foreign_schema', fs.nspname,
                    'foreign_table', ft.relname,
                    'foreign_column', fcol.attname,
                    'on_delete', CASE con.confdeltype
                        WHEN 'a' THEN 'NO ACTION'
                        WHEN 'c' THEN 'CASCADE'
                        WHEN 'r' THEN 'RESTRICT'
                        WHEN 'n' THEN 'SET NULL'
                        WHEN 'd' THEN 'SET DEFAULT'
                        ELSE NULL
                    END
                )
            ) as foreign_keys
        FROM pg_class c
        JOIN pg_constraint con ON con.conrelid = c.oid
        JOIN pg_attribute col ON col.attrelid = con.conrelid AND col.attnum = ANY(con.conkey)
        JOIN pg_class ft ON ft.oid = con.confrelid
        JOIN pg_namespace fs ON fs.oid = ft.relnamespace
        JOIN pg_attribute fcol ON fcol.attrelid = con.confrelid AND fcol.attnum = ANY(con.confkey)
        WHERE con.contype = 'f'
        GROUP BY c.oid
    ),
    index_info AS (
        SELECT 
            c.oid as table_oid,
            jsonb_agg(
                jsonb_build_object(
                    'name', i.relname,
                    'using', am.amname,
                    'columns', (
                        SELECT jsonb_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum))
                        FROM unnest(ix.indkey) WITH ORDINALITY as u(attnum, ord)
                        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = u.attnum
                    )
                )
            ) as indexes
        FROM pg_class c
        JOIN pg_index ix ON ix.indrelid = c.oid
        JOIN pg_class i ON i.oid = ix.indexrelid
        JOIN pg_am am ON am.oid = i.relam
        WHERE NOT ix.indisprimary
        GROUP BY c.oid
    ),
    policy_info AS (
        SELECT 
            c.oid as table_oid,
            jsonb_agg(
                jsonb_build_object(
                    'name', pol.polname,
                    'command', CASE pol.polcmd
                        WHEN 'r' THEN 'SELECT'
                        WHEN 'a' THEN 'INSERT'
                        WHEN 'w' THEN 'UPDATE'
                        WHEN 'd' THEN 'DELETE'
                        WHEN '*' THEN 'ALL'
                    END,
                    'roles', (
                        SELECT string_agg(quote_ident(r.rolname), ', ')
                        FROM pg_roles r
                        WHERE r.oid = ANY(pol.polroles)
                    ),
                    'using', pg_get_expr(pol.polqual, pol.polrelid),
                    'check', pg_get_expr(pol.polwithcheck, pol.polrelid)
                )
            ) as policies
        FROM pg_class c
        JOIN pg_policy pol ON pol.polrelid = c.oid
        GROUP BY c.oid
    ),
    trigger_info AS (
        SELECT 
            c.oid as table_oid,
            jsonb_agg(
                jsonb_build_object(
                    'name', t.tgname,
                    'timing', CASE 
                        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
                        WHEN t.tgtype & 4 = 4 THEN 'AFTER'
                        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
                    END,
                    'events', (
                        CASE WHEN t.tgtype & 1 = 1 THEN 'INSERT'
                             WHEN t.tgtype & 8 = 8 THEN 'DELETE'
                             WHEN t.tgtype & 16 = 16 THEN 'UPDATE'
                             WHEN t.tgtype & 32 = 32 THEN 'TRUNCATE'
                        END
                    ),
                    'statement', pg_get_triggerdef(t.oid)
                )
            ) as triggers
        FROM pg_class c
        JOIN pg_trigger t ON t.tgrelid = c.oid
        WHERE NOT t.tgisinternal
        GROUP BY c.oid
    ),
    table_info AS (
        SELECT DISTINCT 
            c.table_oid,
            c.table_name,
            jsonb_agg(
                jsonb_build_object(
                    'name', c.column_name,
                    'type', c.column_type,
                    'notnull', c.notnull,
                    'default', c.column_default,
                    'identity', c.is_identity,
                    'is_pk', c.is_pk
                ) ORDER BY c.column_name
            ) as columns,
            COALESCE(fk.foreign_keys, '[]'::jsonb) as foreign_keys,
            COALESCE(i.indexes, '[]'::jsonb) as indexes,
            COALESCE(p.policies, '[]'::jsonb) as policies,
            COALESCE(t.triggers, '[]'::jsonb) as triggers
        FROM columns_info c
        LEFT JOIN fk_info fk ON fk.table_oid = c.table_oid
        LEFT JOIN index_info i ON i.table_oid = c.table_oid
        LEFT JOIN policy_info p ON p.table_oid = c.table_oid
        LEFT JOIN trigger_info t ON t.table_oid = c.table_oid
        GROUP BY c.table_oid, c.table_name, fk.foreign_keys, i.indexes, p.policies, t.triggers
    )
    SELECT result || jsonb_build_object(
        'tables',
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'name', table_name,
                    'columns', columns,
                    'foreign_keys', foreign_keys,
                    'indexes', indexes,
                    'policies', policies,
                    'triggers', triggers
                )
            ),
            '[]'::jsonb
        )
    )
    FROM table_info
    INTO result;

    -- Get all functions
    WITH function_info AS (
        SELECT 
            p.proname AS name,
            pg_get_functiondef(p.oid) AS definition
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
        AND p.prokind = 'f'
    )
    SELECT result || jsonb_build_object(
        'functions',
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'name', name,
                    'definition', definition
                )
            ),
            '[]'::jsonb
        )
    )
    FROM function_info
    INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_complete_schema"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audience_personas" (
    "id" "uuid" NOT NULL,
    "persona_type" "public"."persona_type" NOT NULL,
    "description" "text",
    "emotional_state" "text",
    "functional_needs" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."audience_personas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."insight_relations" (
    "id" "uuid" NOT NULL,
    "source_insight_id" "uuid",
    "target_insight_id" "uuid",
    "relation_type" "text"
);


ALTER TABLE "public"."insight_relations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."insight_versions" (
    "id" "uuid" NOT NULL,
    "insight_id" "uuid",
    "version_number" integer,
    "snapshot_data" "jsonb",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."insight_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."insights" (
    "id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "one_line_summary" "text",
    "pillar" "text",
    "info_type" "text",
    "audience_persona_id" "uuid",
    "journey_stage_id" "uuid",
    "status" "text",
    "author_id" "uuid",
    "workspace_id" "uuid",
    "strategic_intent" "text",
    "creative_direction" "text",
    "outcome_goals" "text",
    "brand_positioning" "text",
    "value_priorities" "text",
    "constraints" "text",
    "time_horizon" "text",
    "level_of_abstraction" "text",
    "confidence_score" numeric,
    "source_type" "text",
    "clarification_log" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."insights" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."journey_stages" (
    "id" "uuid" NOT NULL,
    "stage" "public"."journey_stage" NOT NULL,
    "description" "text",
    "key_challenges" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."journey_stages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."output_formats" (
    "id" "uuid" NOT NULL,
    "insight_id" "uuid",
    "format_type" "public"."output_format_type",
    "content" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."output_formats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompt_templates" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "prompt_type" "text",
    "template_text" "text",
    "format_config" "jsonb",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."prompt_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "full_name" "text",
    "role" "text",
    "workspace_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vector_store" (
    "id" "uuid" NOT NULL,
    "insight_id" "uuid",
    "embedding" "text",
    "chunk_count" integer,
    "vector_count" integer,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."vector_store" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."voice_sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "transcript" "text",
    "summary" "text",
    "source_language" "text",
    "mode_detected" "text",
    "insight_created_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."voice_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."workspaces" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "plan_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."workspaces" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audience_personas"
    ADD CONSTRAINT "audience_personas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insight_relations"
    ADD CONSTRAINT "insight_relations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insight_versions"
    ADD CONSTRAINT "insight_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insights"
    ADD CONSTRAINT "insights_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."journey_stages"
    ADD CONSTRAINT "journey_stages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."output_formats"
    ADD CONSTRAINT "output_formats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prompt_templates"
    ADD CONSTRAINT "prompt_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vector_store"
    ADD CONSTRAINT "vector_store_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."voice_sessions"
    ADD CONSTRAINT "voice_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."workspaces"
    ADD CONSTRAINT "workspaces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."insight_relations"
    ADD CONSTRAINT "insight_relations_source_insight_id_fkey" FOREIGN KEY ("source_insight_id") REFERENCES "public"."insights"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."insight_relations"
    ADD CONSTRAINT "insight_relations_target_insight_id_fkey" FOREIGN KEY ("target_insight_id") REFERENCES "public"."insights"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."insight_versions"
    ADD CONSTRAINT "insight_versions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."insight_versions"
    ADD CONSTRAINT "insight_versions_insight_id_fkey" FOREIGN KEY ("insight_id") REFERENCES "public"."insights"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."insights"
    ADD CONSTRAINT "insights_audience_persona_id_fkey" FOREIGN KEY ("audience_persona_id") REFERENCES "public"."audience_personas"("id");



ALTER TABLE ONLY "public"."insights"
    ADD CONSTRAINT "insights_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."insights"
    ADD CONSTRAINT "insights_journey_stage_id_fkey" FOREIGN KEY ("journey_stage_id") REFERENCES "public"."journey_stages"("id");



ALTER TABLE ONLY "public"."insights"
    ADD CONSTRAINT "insights_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id");



ALTER TABLE ONLY "public"."output_formats"
    ADD CONSTRAINT "output_formats_insight_id_fkey" FOREIGN KEY ("insight_id") REFERENCES "public"."insights"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prompt_templates"
    ADD CONSTRAINT "prompt_templates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_workspace_id_fkey" FOREIGN KEY ("workspace_id") REFERENCES "public"."workspaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vector_store"
    ADD CONSTRAINT "vector_store_insight_id_fkey" FOREIGN KEY ("insight_id") REFERENCES "public"."insights"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."voice_sessions"
    ADD CONSTRAINT "voice_sessions_insight_created_id_fkey" FOREIGN KEY ("insight_created_id") REFERENCES "public"."insights"("id");



ALTER TABLE ONLY "public"."voice_sessions"
    ADD CONSTRAINT "voice_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can read" ON "public"."audience_personas" FOR SELECT USING (true);



CREATE POLICY "Anyone can read" ON "public"."journey_stages" FOR SELECT USING (true);



CREATE POLICY "Delete insights in own workspace" ON "public"."insights" FOR DELETE USING (("workspace_id" = ( SELECT "users"."workspace_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Insert formats in own workspace" ON "public"."output_formats" FOR INSERT WITH CHECK (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Insert insights in own workspace" ON "public"."insights" FOR INSERT WITH CHECK (("workspace_id" = ( SELECT "users"."workspace_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Insert own prompt templates" ON "public"."prompt_templates" FOR INSERT WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "Insert own voice sessions" ON "public"."voice_sessions" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Insert relations in own workspace" ON "public"."insight_relations" FOR INSERT WITH CHECK (("source_insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Insert vectors in own workspace" ON "public"."vector_store" FOR INSERT WITH CHECK (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Insert versions in own workspace" ON "public"."insight_versions" FOR INSERT WITH CHECK (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Read formats in own workspace" ON "public"."output_formats" FOR SELECT USING (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Read insights in own workspace" ON "public"."insights" FOR SELECT USING (("workspace_id" = ( SELECT "users"."workspace_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Read own prompt templates" ON "public"."prompt_templates" FOR SELECT USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Read own user data" ON "public"."users" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Read own voice sessions" ON "public"."voice_sessions" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Read own workspace" ON "public"."workspaces" FOR SELECT USING (("id" = ( SELECT "users"."workspace_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Read relations in own workspace" ON "public"."insight_relations" FOR SELECT USING (("source_insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Read vectors in own workspace" ON "public"."vector_store" FOR SELECT USING (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Read versions in own workspace" ON "public"."insight_versions" FOR SELECT USING (("insight_id" IN ( SELECT "insights"."id"
   FROM "public"."insights"
  WHERE ("insights"."workspace_id" = ( SELECT "users"."workspace_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))));



CREATE POLICY "Update insights in own workspace" ON "public"."insights" FOR UPDATE USING (("workspace_id" = ( SELECT "users"."workspace_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))));



CREATE POLICY "Update own user data" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."audience_personas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."insight_relations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."insight_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."insights" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."journey_stages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."output_formats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prompt_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vector_store" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."voice_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workspaces" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_complete_schema"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_complete_schema"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_complete_schema"() TO "service_role";



GRANT ALL ON TABLE "public"."audience_personas" TO "anon";
GRANT ALL ON TABLE "public"."audience_personas" TO "authenticated";
GRANT ALL ON TABLE "public"."audience_personas" TO "service_role";



GRANT ALL ON TABLE "public"."insight_relations" TO "anon";
GRANT ALL ON TABLE "public"."insight_relations" TO "authenticated";
GRANT ALL ON TABLE "public"."insight_relations" TO "service_role";



GRANT ALL ON TABLE "public"."insight_versions" TO "anon";
GRANT ALL ON TABLE "public"."insight_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."insight_versions" TO "service_role";



GRANT ALL ON TABLE "public"."insights" TO "anon";
GRANT ALL ON TABLE "public"."insights" TO "authenticated";
GRANT ALL ON TABLE "public"."insights" TO "service_role";



GRANT ALL ON TABLE "public"."journey_stages" TO "anon";
GRANT ALL ON TABLE "public"."journey_stages" TO "authenticated";
GRANT ALL ON TABLE "public"."journey_stages" TO "service_role";



GRANT ALL ON TABLE "public"."output_formats" TO "anon";
GRANT ALL ON TABLE "public"."output_formats" TO "authenticated";
GRANT ALL ON TABLE "public"."output_formats" TO "service_role";



GRANT ALL ON TABLE "public"."prompt_templates" TO "anon";
GRANT ALL ON TABLE "public"."prompt_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."prompt_templates" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."vector_store" TO "anon";
GRANT ALL ON TABLE "public"."vector_store" TO "authenticated";
GRANT ALL ON TABLE "public"."vector_store" TO "service_role";



GRANT ALL ON TABLE "public"."voice_sessions" TO "anon";
GRANT ALL ON TABLE "public"."voice_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."voice_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."workspaces" TO "anon";
GRANT ALL ON TABLE "public"."workspaces" TO "authenticated";
GRANT ALL ON TABLE "public"."workspaces" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






RESET ALL;
