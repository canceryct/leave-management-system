<template>
  <div class="admin-layout">
    <aside class="admin-sidebar">
      <h2>管理選單</h2>
      <el-menu :default-active="$route.path" :router="true">
        <el-menu-item index="/admin/users">使用者管理</el-menu-item>
        <el-menu-item index="/admin/quotas">名額設定</el-menu-item>
      </el-menu>
    </aside>
    <div class="admin-main">
      <main class="admin-content">
        <router-view />
      </main>
    </div>
  </div>
</template>

<style scoped>
.admin-layout {
  display: flex;
  min-height: 100vh; /* 改為 min-height 以適應內容高度 */
}
.admin-sidebar {
  width: 220px;
  background-color: #ffffff;
  border-right: 1px solid #e0e0e0;
  padding: 1em;
  flex-shrink: 0;
}
.admin-sidebar h2 {
  text-align: center;
  margin-bottom: 1.5rem;
  color: #303133;
}
.admin-main {
  flex-grow: 1;
  display: flex;
  flex-direction: column;
  background-color: #f5f7fa;
}
.admin-header {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  padding: 1rem;
  background-color: #ffffff;
  border-bottom: 1px solid #e0e0e0;
  flex-shrink: 0;
}
.admin-content {
  flex-grow: 1;
  padding: 2em; 
  overflow-y: auto;
}
.el-menu {
  border-right: none;
}

/* --- ✨ 新增的響應式設計 ✨ --- */
@media (max-width: 768px) {
  .admin-layout {
    /* 在小螢幕上，從左右佈局變為上下佈局 */
    flex-direction: column;
  }
  .admin-sidebar {
    width: 100%; /* 側邊欄寬度變為 100% */
    height: auto; /* 高度自動 */
    border-right: none;
    border-bottom: 1px solid #e0e0e0; /* 分隔線改到底部 */
  }
  .admin-content {
    padding: 1em; /* 減少內容區域的邊距 */
  }
}
</style>