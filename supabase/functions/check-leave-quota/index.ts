// 請將以下所有內容，貼到 supabase/functions/check-leave-quota/index.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.0.0';

// CORS Headers，允許我們的 Vue App 呼叫這個函式
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // 處理瀏覽器的 OPTIONS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { leave_date, group_id, leave_type_id } = await req.json();

    // 建立一個有管理員權限的 Supabase client，這樣它才能查詢所有人的資料
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 1. 查詢該組別、該假別的名額限制是多少
    const { data: quotaData, error: quotaError } = await supabaseAdmin
      .from('leave_quotas')
      .select('limit_count')
      .eq('group_id', group_id)
      .eq('leave_type_id', leave_type_id)
      .single();

    if (quotaError) {
      // 如果找不到規則，我們預設為不限制名額，直接允許請假
      console.warn(`No quota rule found for group ${group_id}, leave_type ${leave_type_id}. Allowing.`);
      return new Response(JSON.stringify({ can_take_leave: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    
    const quotaLimit = quotaData.limit_count;

    // 2. 計算在指定日期，該組別、該假別已經有多少人請假
    // 先找出該組別所有成員的 user id
    const { data: profiles, error: profilesError } = await supabaseAdmin.from('profiles').select('id').eq('group_id', group_id);
    if(profilesError) throw profilesError;
    const userIdsInGroup = profiles.map(p => p.id);

    // 再計算這些 user id 中，有多少人在指定日期請了指定假別
    const { count: currentCount, error: countError } = await supabaseAdmin
      .from('leave_records')
      .select('id', { count: 'exact' })
      .eq('leave_date', leave_date)
      .eq('leave_type_id', leave_type_id)
      .in('user_id', userIdsInGroup); // 使用 in 來篩選組內成員
      
    if (countError) throw countError;

    // 3. 比較名額
    if (currentCount >= quotaLimit) {
      // 名額已滿
      return new Response(JSON.stringify({
        can_take_leave: false,
        reason: `名額已滿！該假別當日上限為 ${quotaLimit} 人。`,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    } else {
      // 還有名額
      return new Response(JSON.stringify({ can_take_leave: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});