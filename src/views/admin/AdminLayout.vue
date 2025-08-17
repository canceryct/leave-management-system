<template>
  <div style="display: flex;">
    <aside style="width: 200px; padding: 1em; border-right: 1px solid #ccc; height: 100vh;">
      <h2>管理選單</h2>
      <el-menu :router="true">
        <el-menu-item index="/admin/users">使用者管理</el-menu-item>
        <el-menu-item index="/admin/quotas">名額設定</el-menu-item>
      </el-menu>
    </aside>
    <main style="flex-grow: 1;">
      <router-view />
    </main>
  </div>
</template>