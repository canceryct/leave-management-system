import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.0.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') { return new Response('ok', { headers: corsHeaders }); }
  try {
    const { email, password, username, full_name, group_id, role } = await req.json();
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: { user }, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: email, password: password, email_confirm: true,
    });
    if (createError) throw createError;

    // ✨ 關鍵修改：移除了 force_password_change: true
    const { error: updateError } = await supabaseAdmin.from('profiles').update({
      username: username, full_name: full_name, group_id: group_id, role: role,
    }).eq('id', user.id);
    if (updateError) throw updateError;

    return new Response(JSON.stringify({ message: "使用者建立成功" }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 });
  }
});