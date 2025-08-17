// supabase/functions/update-user/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.0.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 接收所有可能被更新的欄位
    const { id, email, full_name, role, group_id } = await req.json();

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 步驟一：更新 Auth 使用者的 Email (如果提供了 email)
    if (email) {
      const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(
        id,
        { email: email }
      );
      if (authError) throw authError;
    }

    // 步驟二：更新 profiles 表中的其餘資料
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .update({
        full_name: full_name,
        role: role,
        group_id: group_id,
      })
      .eq('id', id);
    if (profileError) throw profileError;

    return new Response(JSON.stringify({ message: "使用者更新成功" }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 });
  }
});