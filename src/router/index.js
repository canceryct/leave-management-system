import { createRouter, createWebHistory } from 'vue-router';
import { supabase } from '../supabase';

import Login from '../views/Login.vue';
import Dashboard from '../views/Dashboard.vue';
import UpdatePassword from '../views/UpdatePassword.vue';
import AdminLayout from '../views/admin/AdminLayout.vue';
import UserManagement from '../views/admin/UserManagement.vue';
import QuotaManagement from '../views/admin/QuotaManagement.vue';
import DailyView from '../views/DailyView.vue';
import DispatchForm from '../views/DispatchForm.vue';

const routes = [
  { path: '/', name: 'Home', redirect: '/login' },
  { path: '/login', name: 'Login', component: Login },
  { path: '/dashboard', name: 'Dashboard', component: Dashboard, meta: { requiresAuth: true } },
  { path: '/update-password', name: 'UpdatePassword', component: UpdatePassword },
  { 
    path: '/dispatch-form', 
    name: 'DispatchForm', 
    component: DispatchForm, 
    meta: { requiresAuth: true } // 這個頁面需要登入才能訪問
  },
  {
    path: '/admin', component: AdminLayout, meta: { requiresAuth: true, requiresAdmin: true }, redirect: '/admin/users',
    children: [
      { path: 'users', name: 'UserManagement', component: UserManagement },
      { path: 'quotas', name: 'QuotaManagement', component: QuotaManagement }
    ]
  },
  { 
    path: '/daily-view', 
    name: 'DailyView', 
    component: DailyView, 
    meta: { requiresAuth: true } 
  }
];

const router = createRouter({ history: createWebHistory(), routes });

// ✨ 1. 在這裡定設定閒置登出時間 (5分鐘)
const INACTIVITY_TIMEOUT = 5 * 60 * 1000; 

router.beforeEach(async (to, from, next) => {
  // 1. 檢查閒置是否超時
  const lastActivity = localStorage.getItem('lastActivity');
  if (lastActivity && (new Date().getTime() - Number(lastActivity) > INACTIVITY_TIMEOUT)) {
    await supabase.auth.signOut();
    localStorage.removeItem('lastActivity'); 
  }

  // 白名單模式依然是最穩固的，直接放行這些頁面
  const publicPages = ['/login', '/update-password'];
  if (publicPages.includes(to.path)) {
    return next();
  }

  // 對於所有其他頁面，getSession 現在可以穩定地工作了
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    return next('/login');
  }

  // 登入後的檢查
  const { data: profile } = await supabase.from('profiles').select('role').eq('id', session.user.id).single();
  if (!profile) {
    await supabase.auth.signOut();
    return next('/login');
  }

  const requiresAdmin = to.matched.some(record => record.meta.requiresAdmin);
  if (requiresAdmin && profile.role !== 'admin') {
    alert('權限不足！');
    return next('/dashboard');
  }

  next();
});

export default router;