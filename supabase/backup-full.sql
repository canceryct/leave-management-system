

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


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."leave_request_response" AS (
	"success" boolean,
	"message" "text"
);


ALTER TYPE "public"."leave_request_response" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_calendar_events"() RETURNS TABLE("id" bigint, "user_id" "uuid", "leave_date" "date", "leave_period" "text", "full_name" "text", "leave_type_name" "text", "proxy_user_name" "text", "proxy_user_id" "text", "leave_type_id" bigint)
    LANGUAGE "sql"
    AS $_$
  -- 這個查詢只負責連接資料表，不包含任何 WHERE 條件
  -- 所有的過濾都將交給下面步驟設定的 RLS 規則來處理
  SELECT
    lr.id,
    lr.user_id,
    lr.leave_date,
    lr.leave_period,
    p_user.full_name,
    lt.name as leave_type_name,
    CASE
      WHEN lr.proxy_user_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (SELECT p_proxy.full_name FROM public.profiles p_proxy WHERE p_proxy.id = lr.proxy_user_id::uuid)
      ELSE lr.proxy_user_id
    END as proxy_user_name,
    lr.proxy_user_id,
    lr.leave_type_id
  FROM
    public.leave_records lr
    LEFT JOIN public.profiles p_user ON lr.user_id = p_user.id
    LEFT JOIN public.leave_types lt ON lr.leave_type_id = lt.id;
$_$;


ALTER FUNCTION "public"."get_calendar_events"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_group_quotas_list"() RETURNS TABLE("id" bigint, "name" "text", "limit_count" integer)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    g.id,
    g.name,
    gq.limit_count
  FROM
    public.groups g
    LEFT JOIN public.group_leave_quotas gq ON g.id = gq.group_id
  -- ✨ 關鍵修改：在查詢的最後加上這一行排序指令 ✨
  ORDER BY g.id ASC;
$$;


ALTER FUNCTION "public"."get_group_quotas_list"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_group_id"() RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  my_group_id BIGINT;
BEGIN
  -- 這段程式碼會以更高的權限執行，繞過 RLS 檢查，從而避免無限遞迴
  SELECT group_id INTO my_group_id
  FROM public.profiles
  WHERE id = auth.uid();
  RETURN my_group_id;
END;
$$;


ALTER FUNCTION "public"."get_my_group_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_role"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- 回傳當前登入使用者的角色
  RETURN (SELECT role FROM public.profiles WHERE id = auth.uid());
END;
$$;


ALTER FUNCTION "public"."get_my_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_management_list"() RETURNS TABLE("id" "uuid", "username" "text", "full_name" "text", "email" "text", "role" "text", "group_id" bigint, "group_name" "text")
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    p.id,
    p.username,
    p.full_name,
    u.email,
    p.role,
    g.id as group_id,
    g.name as group_name
  FROM
    public.profiles p
    LEFT JOIN auth.users u ON p.id = u.id
    LEFT JOIN public.groups g ON p.group_id = g.id
  -- ✨ 關鍵修改：在查詢的最後加上這一行排序指令 ✨
  ORDER BY p.username ASC;
$$;


ALTER FUNCTION "public"."get_user_management_list"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (new.id, new.raw_user_meta_data->>'full_name');
  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_leave"("p_leave_date" "date", "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") RETURNS "public"."leave_request_response"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id UUID := auth.uid(); v_group_id BIGINT; v_quota_limit INT; v_am_count INT := 0; v_pm_count INT := 0; is_acting_as_proxy BOOLEAN; v_response public.leave_request_response;
BEGIN
  IF p_leave_date < CURRENT_DATE THEN v_response := (FALSE, '登記失敗：無法登記過去的日期。'); RETURN v_response; END IF;
  SELECT group_id INTO v_group_id FROM public.profiles WHERE id = v_user_id;
  IF v_group_id IS NULL THEN v_response := (FALSE, '錯誤：找不到您的組別資訊。'); RETURN v_response; END IF;
  SELECT limit_count INTO v_quota_limit FROM public.group_leave_quotas WHERE group_id = v_group_id;
  IF v_quota_limit IS NULL THEN v_quota_limit := 999; END IF;
  SELECT count(*) FILTER (WHERE lr.leave_period IN ('full', 'am')), count(*) FILTER (WHERE lr.leave_period IN ('full', 'pm')) INTO v_am_count, v_pm_count FROM public.leave_records lr WHERE lr.leave_date = p_leave_date AND lr.group_id = v_group_id;
  IF p_leave_period = 'am' AND v_am_count >= v_quota_limit THEN v_response := (FALSE, '名額不足！該日上午已有 ' || v_am_count || ' 人請假，已達上限 ' || v_quota_limit || ' 人。'); RETURN v_response; END IF;
  IF p_leave_period = 'pm' AND v_pm_count >= v_quota_limit THEN v_response := (FALSE, '名額不足！該日下午已有 ' || v_pm_count || ' 人請假，已達上限 ' || v_quota_limit || ' 人。'); RETURN v_response; END IF;
  IF p_leave_period = 'full' THEN
    IF v_am_count >= v_quota_limit THEN v_response := (FALSE, '名額不足！該日上午已有 ' || v_am_count || ' 人請假，已達上限 ' || v_quota_limit || ' 人。'); RETURN v_response; END IF;
    IF v_pm_count >= v_quota_limit THEN v_response := (FALSE, '名額不足！該日下午已有 ' || v_pm_count || ' 人請假，已達上限 ' || v_quota_limit || ' 人。'); RETURN v_response; END IF;
  END IF;
  INSERT INTO public.leave_records(user_id, leave_date, leave_type_id, proxy_user_id, leave_period, group_id) VALUES (v_user_id, p_leave_date, p_leave_type_id, p_proxy_user_id, p_leave_period, v_group_id);
  v_response := (TRUE, '假單登記成功！'); RETURN v_response;
END;
$$;


ALTER FUNCTION "public"."request_leave"("p_leave_date" "date", "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_password_as_changed"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  -- 儘管有最高權限，我們仍然用 WHERE 條件確保它絕對只會更新當前登入使用者自己的旗標
  UPDATE public.profiles
  SET force_password_change = false
  WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."set_password_as_changed"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_leave_record"("p_record_id" bigint, "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") RETURNS "public"."leave_request_response"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_leave_date DATE;
  v_group_id BIGINT;
  v_quota_limit INT;
  v_am_count INT := 0;
  v_pm_count INT := 0;
  v_response public.leave_request_response;
BEGIN
  -- 1. 先確認這筆假單是屬於當前使用者的
  SELECT leave_date, group_id INTO v_leave_date, v_group_id
  FROM public.leave_records
  WHERE id = p_record_id AND user_id = v_user_id;

  IF v_leave_date IS NULL THEN
    v_response := (FALSE, '更新失敗：找不到或無權限修改此假單。');
    RETURN v_response;
  END IF;

  -- 2. 獲取名額上限
  SELECT limit_count INTO v_quota_limit FROM public.group_leave_quotas WHERE group_id = v_group_id;
  IF v_quota_limit IS NULL THEN v_quota_limit := 999; END IF;

  -- 3. 計算「除了我這筆之外」的當天已請假人數
  SELECT
    count(*) FILTER (WHERE lr.leave_period IN ('full', 'am')),
    count(*) FILTER (WHERE lr.leave_period IN ('full', 'pm'))
  INTO v_am_count, v_pm_count
  FROM public.leave_records lr
  WHERE lr.leave_date = v_leave_date AND lr.group_id = v_group_id AND lr.id != p_record_id;

  -- 4. 根據「修改後」的時段，進行名額檢查
  IF p_leave_period = 'am' AND v_am_count >= v_quota_limit THEN
    v_response := (FALSE, '名額不足！無法將假單修改至該日上午。'); RETURN v_response;
  END IF;
  IF p_leave_period = 'pm' AND v_pm_count >= v_quota_limit THEN
    v_response := (FALSE, '名額不足！無法將假單修改至該日下午。'); RETURN v_response;
  END IF;
  IF p_leave_period = 'full' THEN
    IF v_am_count >= v_quota_limit OR v_pm_count >= v_quota_limit THEN
      v_response := (FALSE, '名額不足！無法將假單修改為全天。'); RETURN v_response;
    END IF;
  END IF;
  
  -- 5. 所有檢查通過，更新假單
  UPDATE public.leave_records
  SET
    leave_type_id = p_leave_type_id,
    proxy_user_id = p_proxy_user_id,
    leave_period = p_leave_period
  WHERE id = p_record_id;

  v_response := (TRUE, '假單更新成功！');
  RETURN v_response;
END;
$$;


ALTER FUNCTION "public"."update_leave_record"("p_record_id" bigint, "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."group_leave_quotas" (
    "group_id" bigint NOT NULL,
    "limit_count" integer NOT NULL,
    CONSTRAINT "group_leave_quotas_limit_count_check" CHECK (("limit_count" >= 0))
);


ALTER TABLE "public"."group_leave_quotas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."groups" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."groups" OWNER TO "postgres";


ALTER TABLE "public"."groups" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."groups_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."leave_records" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "leave_date" "date" NOT NULL,
    "leave_type_id" bigint NOT NULL,
    "proxy_user_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "leave_period" "text" DEFAULT 'full'::"text" NOT NULL,
    "group_id" bigint
);


ALTER TABLE "public"."leave_records" OWNER TO "postgres";


ALTER TABLE "public"."leave_records" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."leave_records_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."leave_types" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."leave_types" OWNER TO "postgres";


ALTER TABLE "public"."leave_types" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."leave_types_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "group_id" bigint,
    "full_name" "text",
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    "username" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


ALTER TABLE ONLY "public"."group_leave_quotas"
    ADD CONSTRAINT "group_leave_quotas_pkey" PRIMARY KEY ("group_id");



ALTER TABLE ONLY "public"."groups"
    ADD CONSTRAINT "groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_records"
    ADD CONSTRAINT "leave_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_types"
    ADD CONSTRAINT "leave_types_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



CREATE INDEX "idx_profiles_username" ON "public"."profiles" USING "btree" ("username");



ALTER TABLE ONLY "public"."group_leave_quotas"
    ADD CONSTRAINT "group_leave_quotas_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id");



ALTER TABLE ONLY "public"."leave_records"
    ADD CONSTRAINT "leave_records_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id");



ALTER TABLE ONLY "public"."leave_records"
    ADD CONSTRAINT "leave_records_leave_type_id_fkey" FOREIGN KEY ("leave_type_id") REFERENCES "public"."leave_types"("id");



ALTER TABLE ONLY "public"."leave_records"
    ADD CONSTRAINT "leave_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "public"."groups"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Admins have full access to quotas." ON "public"."group_leave_quotas" USING (("public"."get_my_role"() = 'admin'::"text")) WITH CHECK (("public"."get_my_role"() = 'admin'::"text"));



CREATE POLICY "Any logged-in user can view all leave records." ON "public"."leave_records" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can read groups and leave_types." ON "public"."groups" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can read groups and leave_types." ON "public"."leave_types" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can view all leave records." ON "public"."leave_records" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Authenticated users can view all profiles." ON "public"."profiles" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Leave records are viewable by same-group members." ON "public"."leave_records" FOR SELECT USING (("group_id" = "public"."get_my_group_id"()));



CREATE POLICY "Profiles are viewable/editable by the owner." ON "public"."profiles" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can create/delete their own leave records." ON "public"."leave_records" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."group_leave_quotas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."groups" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leave_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leave_types" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."group_leave_quotas";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."leave_records";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."get_calendar_events"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_calendar_events"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_calendar_events"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_group_quotas_list"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_group_quotas_list"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_group_quotas_list"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_group_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_group_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_group_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_management_list"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_management_list"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_management_list"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."request_leave"("p_leave_date" "date", "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."request_leave"("p_leave_date" "date", "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_leave"("p_leave_date" "date", "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_password_as_changed"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_password_as_changed"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_password_as_changed"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_leave_record"("p_record_id" bigint, "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_leave_record"("p_record_id" bigint, "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_leave_record"("p_record_id" bigint, "p_leave_type_id" bigint, "p_proxy_user_id" "text", "p_leave_period" "text") TO "service_role";


















GRANT ALL ON TABLE "public"."group_leave_quotas" TO "anon";
GRANT ALL ON TABLE "public"."group_leave_quotas" TO "authenticated";
GRANT ALL ON TABLE "public"."group_leave_quotas" TO "service_role";



GRANT ALL ON TABLE "public"."groups" TO "anon";
GRANT ALL ON TABLE "public"."groups" TO "authenticated";
GRANT ALL ON TABLE "public"."groups" TO "service_role";



GRANT ALL ON SEQUENCE "public"."groups_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."groups_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."groups_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."leave_records" TO "anon";
GRANT ALL ON TABLE "public"."leave_records" TO "authenticated";
GRANT ALL ON TABLE "public"."leave_records" TO "service_role";



GRANT ALL ON SEQUENCE "public"."leave_records_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."leave_records_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."leave_records_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."leave_types" TO "anon";
GRANT ALL ON TABLE "public"."leave_types" TO "authenticated";
GRANT ALL ON TABLE "public"."leave_types" TO "service_role";



GRANT ALL ON SEQUENCE "public"."leave_types_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."leave_types_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."leave_types_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
