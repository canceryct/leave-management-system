import { createRouter, createWebHistory } from 'vue-router';
import { supabase } from '../supabase';

import Login from '../views/Login.vue';
import Dashboard from '../views/Dashboard.vue';
import UpdatePassword from '../views/UpdatePassword.vue';
import AdminLayout from '../views/admin/AdminLayout.vue';
import UserManagement from '../views/admin/UserManagement.vue';
import QuotaManagement from '../views/admin/QuotaManagement.vue';

const routes = [
  { path: '/', name: 'Home', redirect: '/login' },
  { path: '/login', name: 'Login', component: Login },
  { path: '/dashboard', name: 'Dashboard', component: Dashboard, meta: { requiresAuth: true } },
  { path: '/update-password', name: 'UpdatePassword', component: UpdatePassword },
  {
    path: '/admin', component: AdminLayout, meta: { requiresAuth: true, requiresAdmin: true }, redirect: '/admin/users',
    children: [
      { path: 'users', name: 'UserManagement', component: UserManagement },
      { path: 'quotas', name: 'QuotaManagement', component: QuotaManagement }
    ]
  }
];

const router = createRouter({ history: createWebHistory(), routes });

router.beforeEach(async (to, from, next) => {
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