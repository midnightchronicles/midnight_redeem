(() => {
    const doc = document;
    const root = doc.documentElement;
    const PRN = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'midnight_redeem';
  
    let currentLocale = 'en';
    let localeData = {};
    let fallbackLocale = 'en';
    let aiEnabled = true;
    let isOwnerUser = false;
    let activeRuntimeConfigTab = 'general';
    let runtimeConfigCache = {};

    function setupOwnerOnlyUI() {
      doc.querySelectorAll('.owner-only-setting').forEach(el => {
        el.classList.toggle('hidden', !isOwnerUser);
      });
      doc.querySelectorAll('.owner-only-notice').forEach(el => {
        el.classList.toggle('hidden', isOwnerUser);
      });
      const panel = doc.getElementById('chatSettingsPanel');
      if (panel) {
        panel.classList.toggle('is-readonly', !isOwnerUser);
      }
    }

    function refreshOwnerSettingsIfVisible() {
      const aiSection = doc.getElementById('aiChatSettingsSection');
      if (aiSection && !aiSection.classList.contains('hidden')) {
        const chatSettings = doc.getElementById('chatSettingsSection');
        if (chatSettings && !chatSettings.classList.contains('hidden')) {
          loadAIChatSettings();
        }
      }
      const runtimeSection = doc.getElementById('runtimeConfigSection');
      if (runtimeSection && !runtimeSection.classList.contains('hidden')) {
        loadRuntimeConfigTab(activeRuntimeConfigTab);
      }
    }

    function syncManualRewardFields(prefix) {
      const type = doc.getElementById(`${prefix}RewardType`)?.value || 'item';
      const nameEl = doc.getElementById(`${prefix}RewardName`);
      const labelEl = doc.getElementById(`${prefix}RewardLabel`);
      const amountEl = doc.getElementById(`${prefix}RewardAmount`);

      if (type === 'money') {
        if (nameEl) {
          nameEl.style.display = 'none';
          nameEl.value = '';
        }
        if (labelEl) {
          labelEl.style.display = 'none';
          labelEl.value = '';
        }
        if (amountEl) amountEl.style.display = '';
      } else if (type === 'vehicle') {
        if (nameEl) {
          nameEl.style.display = '';
          nameEl.placeholder = 'Vehicle spawn name';
        }
        if (labelEl) {
          labelEl.style.display = '';
          labelEl.placeholder = 'Display label (e.g. Adder)';
        }
        if (amountEl) {
          amountEl.style.display = 'none';
          amountEl.value = '1';
        }
      } else {
        if (nameEl) {
          nameEl.style.display = '';
          nameEl.placeholder = 'Item spawn name';
        }
        if (labelEl) {
          labelEl.style.display = '';
          labelEl.placeholder = 'Display label (e.g. Water Bottle)';
        }
        if (amountEl) amountEl.style.display = '';
      }
    }

    function escapeHtml(str) {
      if (str == null) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }
  
    function toast(title, message, type='info', ms=2500){
      const host = doc.getElementById('toast-root');
      if (!host) return;
      const el = doc.createElement('div');
      el.className = `toast ${type}`;
      el.innerHTML = `<div class="t-title">${escapeHtml(title||'Notice')}</div><div>${escapeHtml(message||'')}</div>`;
      host.appendChild(el);
      setTimeout(()=>{ el.style.opacity='0'; el.style.transform='translateY(-6px)'; setTimeout(()=>el.remove(), 350); }, ms);
    }
  
    const themeToggle = doc.getElementById('themeToggle');
    
    function initTheme() {
      const saved = localStorage.getItem('mr_theme') || 'dark';
      applyTheme();
    }
    
    function applyTheme() {
      const isLight = localStorage.getItem('mr_theme') === 'light';
      root.classList.toggle('theme-light', isLight);
      document.body.classList.toggle('theme-light', isLight);
      const label = document.querySelector('.theme-label');
      const icon = document.querySelector('#themeToggle .icon');
      if (label) label.textContent = isLight ? 'Light' : 'Dark';
      if (icon) icon.innerHTML = isLight ? '<i class=\'fas fa-sun\'></i>' : '<i class=\'fas fa-moon\'></i>';
      
      // Clear text color overrides to let theme handle them
      const textColors = ['text', 'text-muted', 'text-dim', 'text-secondary', 'text-tertiary'];
      textColors.forEach(colorVar => {
        root.style.removeProperty(`--${colorVar}`);
      });
      
      // Reload custom colors to respect theme change
      loadCustomColors();
    }
  
    async function loadLocale(locale) {
      try {
        let response;
        let success = false;
        let lastError = null;

        const paths = [
          `./locales/${locale}.json`,
          `/locales/${locale}.json`,
          `../locales/${locale}.json`,
          `locales/${locale}.json`
        ];
        
        for (const path of paths) {
          try {
            response = await fetch(path);
            if (response && response.ok) {
              success = true;
              break;
            } else {
              lastError = `HTTP ${response?.status}`;
            }
          } catch (e) {
            lastError = e.message;
          }
        }
        
        if (success && response && response.ok) {
          try {
            const buffer = await response.arrayBuffer();
            const decoder = new TextDecoder('utf-8');
            const text = decoder.decode(buffer);
            localeData = JSON.parse(text);
            currentLocale = locale;
            localStorage.setItem('mr_locale', locale);
            applyLocale();
            return true;
          } catch (parseError) {
            if (locale !== fallbackLocale) {
              return await loadLocale(fallbackLocale);
            }
            return false;
          }
        } else {
          if (locale !== fallbackLocale) {
            return await loadLocale(fallbackLocale);
          }
          return false;
        }
      } catch (error) {
        if (locale !== fallbackLocale) {
          return await loadLocale(fallbackLocale);
        }
        return false;
      }
    }
  
    function t(key, ...args) {
      let text = localeData[key] || key;
      if (args.length > 0) {
        args.forEach((arg, index) => {
          text = text.replace(`%s`, arg);
        });
      }
      return text;
    }

    window.t = t;

    function setDisplayedVersion(version) {
      const label = version ? `v${version}` : 'v—';
      const sidebarEl = doc.getElementById('sidebarVersion');
      if (sidebarEl) sidebarEl.textContent = label;
    }

    function updateVersionPanel(versionInfo, checking) {
      const currentEl = doc.getElementById('versionCurrent');
      const latestEl = doc.getElementById('versionLatest');
      const latestRow = doc.getElementById('versionLatestRow');
      const statusEl = doc.getElementById('versionStatusText');
      const updateBlock = doc.getElementById('versionUpdateBlock');
      const notesEl = doc.getElementById('versionUpdateNotes');
      const linkEl = doc.getElementById('versionReleaseLink');

      if (!currentEl || !statusEl) return;

      if (checking) {
        currentEl.textContent = versionInfo?.current || '—';
        if (versionInfo?.current) setDisplayedVersion(versionInfo.current);
        if (latestRow) latestRow.classList.add('hidden');
        if (updateBlock) {
          updateBlock.classList.add('hidden');
          updateBlock.classList.remove('is-outdated', 'is-ahead');
        }
        statusEl.textContent = t('UI_VERSION_CHECKING');
        statusEl.className = 'version-status-text';
        return;
      }

      const info = versionInfo || {};
      const current = info.current || '—';
      currentEl.textContent = current;
      if (info.current) setDisplayedVersion(info.current);

      if (info.error && info.error !== 'disabled') {
        if (latestRow) latestRow.classList.add('hidden');
        if (updateBlock) {
          updateBlock.classList.add('hidden');
          updateBlock.classList.remove('is-outdated', 'is-ahead');
        }
        statusEl.textContent = t('UI_VERSION_CHECK_FAILED');
        statusEl.className = 'version-status-text is-error';
        return;
      }

      if (info.updateAvailable) {
        if (latestRow) latestRow.classList.remove('hidden');
        if (latestEl) latestEl.textContent = info.latestTag || info.latest || '—';
        if (updateBlock) {
          updateBlock.classList.remove('hidden', 'is-ahead');
          updateBlock.classList.add('is-outdated');
        }
        const titleEl = updateBlock?.querySelector('.version-update-title');
        if (titleEl) titleEl.textContent = t('UI_VERSION_UPDATE_AVAILABLE');
        if (notesEl) {
          notesEl.className = 'version-update-notes';
          notesEl.textContent = (info.releaseNotes && info.releaseNotes.trim())
            ? info.releaseNotes.trim()
            : t('UI_VERSION_RELEASE_NOTES');
        }
        if (linkEl) {
          linkEl.classList.remove('hidden');
          if (info.releaseUrl) linkEl.href = info.releaseUrl;
        }
        statusEl.textContent = t('UI_VERSION_UPDATE_AVAILABLE');
        statusEl.className = 'version-status-text is-outdated';
      } else if (info.aheadOfRelease) {
        if (latestRow) latestRow.classList.remove('hidden');
        if (latestEl) latestEl.textContent = info.latestTag || info.latest || '—';
        if (updateBlock) {
          updateBlock.classList.remove('hidden', 'is-outdated');
          updateBlock.classList.add('is-ahead');
        }
        const titleEl = updateBlock?.querySelector('.version-update-title');
        if (titleEl) titleEl.textContent = t('UI_VERSION_AHEAD_TITLE');
        if (notesEl) {
          notesEl.className = 'version-update-notes is-ahead';
          notesEl.textContent = t('UI_VERSION_AHEAD_DETAIL');
        }
        if (linkEl) linkEl.classList.add('hidden');
        statusEl.textContent = t('UI_VERSION_AHEAD_OF_RELEASE');
        statusEl.className = 'version-status-text is-ahead';
      } else {
        if (latestRow) latestRow.classList.remove('hidden');
        if (latestEl) latestEl.textContent = info.latestTag || info.latest || info.current || '—';
        if (updateBlock) updateBlock.classList.add('hidden');
        if (updateBlock) updateBlock.classList.remove('is-outdated', 'is-ahead');
        statusEl.textContent = t('UI_VERSION_UP_TO_DATE');
        statusEl.className = 'version-status-text is-ok';
      }
    }

    async function loadVersionInfo(refresh) {
      updateVersionPanel(null, true);
      try {
        const info = await nuiRet('getVersionInfo', { refresh: !!refresh });
        updateVersionPanel(info, false);
      } catch (_) {
        updateVersionPanel({ error: 'failed', current: '—' }, false);
      }
    }
  
    function applyLocale() {
      doc.querySelectorAll('[data-locale]').forEach(element => {
        const key = element.getAttribute('data-locale');
        if (key) {
          const translatedText = t(key);
          element.textContent = translatedText;
        }
      });

      doc.querySelectorAll('[data-locale-placeholder]').forEach(element => {
        const key = element.getAttribute('data-locale-placeholder');
        if (key) {
          const translated = t(key);
          element.setAttribute('placeholder', translated);
        }
      });
      
      const languageSelector = doc.getElementById('languageSelector');
      if (languageSelector && Object.keys(localeData).length > 0) {
        const currentValue = languageSelector.value;
        const languages = {
          'en': 'UI_LANGUAGE_ENGLISH',
          'fr': 'UI_LANGUAGE_FRENCH',
          'es': 'UI_LANGUAGE_SPANISH',
          'de': 'UI_LANGUAGE_GERMAN',
          'it': 'UI_LANGUAGE_ITALIAN',
          'pt': 'UI_LANGUAGE_PORTUGUESE',
          'ru': 'UI_LANGUAGE_RUSSIAN',
          'ja': 'UI_LANGUAGE_JAPANESE',
          'ko': 'UI_LANGUAGE_KOREAN',
          'zh': 'UI_LANGUAGE_CHINESE',
          'ar': 'UI_LANGUAGE_ARABIC',
          'hi': 'UI_LANGUAGE_HINDI',
          'nl': 'UI_LANGUAGE_DUTCH',
          'sv': 'UI_LANGUAGE_SWEDISH',
          'no': 'UI_LANGUAGE_NORWEGIAN',
          'da': 'UI_LANGUAGE_DANISH',
          'fi': 'UI_LANGUAGE_FINNISH',
          'pl': 'UI_LANGUAGE_POLISH',
          'cs': 'UI_LANGUAGE_CZECH',
          'hu': 'UI_LANGUAGE_HUNGARIAN',
          'ro': 'UI_LANGUAGE_ROMANIAN',
          'el': 'UI_LANGUAGE_GREEK',
          'tr': 'UI_LANGUAGE_TURKISH',
          'he': 'UI_LANGUAGE_HEBREW',
          'th': 'UI_LANGUAGE_THAI',
          'vi': 'UI_LANGUAGE_VIETNAMESE'
        };
        
        Object.entries(languages).forEach(([code, key]) => {
          const option = languageSelector.querySelector(`option[value="${code}"]`);
          if (option && localeData[key]) {
            option.textContent = localeData[key];
          }
        });
        languageSelector.value = currentValue;
      }
    }
    
    function updatePermissionsUI(permissions) {
      
      const currentRoleElement = doc.getElementById('currentRole');
      if (currentRoleElement) {
        const role = permissions.role || 'staff';
        currentRoleElement.textContent = role.toUpperCase();
        currentRoleElement.classList.remove('loading');

        currentRoleElement.className = 'role-badge';
        if (role === 'owner') {
          currentRoleElement.classList.add('owner');
        } else if (role === 'manager') {
          currentRoleElement.classList.add('manager');
        } else {
          currentRoleElement.classList.add('staff');
        }
      }
      
      const permissionLevelElement = doc.getElementById('permissionLevel');
      const level = permissions.level || 1;
      isOwnerUser = permissions.role === 'owner' || level >= 3 || !!(permissions.permissions && permissions.permissions.hasFullAccess);
      setupOwnerOnlyUI();

      if (permissionLevelElement) {
        permissionLevelElement.textContent = level.toString();
        permissionLevelElement.classList.remove('loading');

        permissionLevelElement.className = 'level-badge';
        if (level >= 3) {
          permissionLevelElement.classList.add('owner');
        } else if (level >= 2) {
          permissionLevelElement.classList.add('manager');
        } else {
          permissionLevelElement.classList.add('staff');
        }
      }

      refreshOwnerSettingsIfVisible();
      

      const permissionSection = doc.querySelector('.permission-info');
      if (permissionSection) {
        const loadingElements = permissionSection.querySelectorAll('.loading');
        loadingElements.forEach(el => el.classList.remove('loading'));
      }
      

      const permissionActions = doc.getElementById('permissionActions');
      if (permissionActions) {
        const level = permissions.level || 1;
        if (level >= 2) {
          permissionActions.style.display = 'block';

          loadUserList();
        } else {
          permissionActions.style.display = 'none';
        }
      }
      
      const codeSettingsSection = doc.getElementById('codeSettingsSection');
      if (codeSettingsSection) {
        const level = permissions.level || 1;
        if (level >= 2) {
          codeSettingsSection.style.display = 'block';
        } else {
          codeSettingsSection.style.display = 'none';
        }
      }
      
      const bulkGenerateBtn = doc.getElementById('bulkGenerateBtn');
      if (bulkGenerateBtn) {
        const level = permissions.level || 1;
        const canBulkGenerate = level >= 2;
        if (canBulkGenerate) {
          bulkGenerateBtn.style.display = '';
        } else {
          bulkGenerateBtn.style.display = 'none';
        }
      }
      
      const permissionsBtn = doc.getElementById('permissionsBtn');
      if (permissionsBtn) {
        const level = permissions.level || 1;
        const canManagePermissions = (permissions.permissions && permissions.permissions.canManagePermissions) || level >= 2;
        if (canManagePermissions) {
          permissionsBtn.style.display = '';
        } else {
          permissionsBtn.style.display = 'none';
        }
      }
      
      const editCodeBtn = doc.getElementById('editCodeBtn');
      if (editCodeBtn) {
        const level = permissions.level || 1;
        const canEdit = (permissions.permissions && permissions.permissions.canEdit) || level >= 2;
        if (canEdit) {
          editCodeBtn.style.display = '';
        } else {
          editCodeBtn.style.display = 'none';
        }
      }
      
      const deleteCodeBtn = doc.getElementById('deleteCodeBtn');
      if (deleteCodeBtn) {
        const level = permissions.level || 1;
        const canDelete = (permissions.permissions && permissions.permissions.canDelete) || level >= 2;
        if (canDelete) {
          deleteCodeBtn.style.display = '';
        } else {
          deleteCodeBtn.style.display = 'none';
        }
      }
      
      const deleteEdit = doc.getElementById('deleteEdit');
      if (deleteEdit) {
        const level = permissions.level || 1;
        const canDelete = (permissions.permissions && permissions.permissions.canDelete) || level >= 2;
        if (canDelete) {
          deleteEdit.style.display = '';
        } else {
          deleteEdit.style.display = 'none';
        }
      }
    }
  
    async function fetchPreFilledRewards() {
      if (window._preFilledRewardsCache) {
        return window._preFilledRewardsCache;
      }
      const templates = await nuiRet('getPreFilledRewards', {});
      window._preFilledRewardsCache = templates;
      return templates;
    }

    async function fetchSavedTemplates() {
      if (window._savedTemplatesCache) {
        return window._savedTemplatesCache;
      }
      const result = await nuiRet('getSavedTemplates', {});
      window._savedTemplatesCache = result;
      return result;
    }

    function clearTemplateCaches() {
      window._savedTemplatesCache = null;
    }

    async function initializeLocale() {
      const savedLocale = localStorage.getItem('mr_locale');

      if (savedLocale) {
        const success = await loadLocale(savedLocale);
        if (success) {
          return;
        }
      }

      await loadLocale(fallbackLocale);
    }
  
    const routes = {
      'admin-dashboard': doc.getElementById('route-admin-dashboard'),
      'ai-generation': doc.getElementById('route-ai-generation'),
      'admin-codes': doc.getElementById('route-admin-codes'),
      'admin-settings': doc.getElementById('route-admin-settings'),
      'code-view': doc.getElementById('route-code-view'),
      'code-edit': doc.getElementById('route-code-edit'),
      'player': doc.getElementById('route-player'),
    };
    const navItems = Array.from(doc.querySelectorAll('.nav-item'));
    const breadcrumbs = doc.getElementById('breadcrumbs');
    let currentRoute = 'admin-dashboard';

    let isRouteTransitioning = false;
    let lastRouteSwitchAt = 0;
    const ROUTE_DEBOUNCE_MS = 150;

    function showRoute(name) {
      const nowTs = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
      if (isRouteTransitioning) return;
      if (name === 'ai-generation' && !aiEnabled) {
        name = 'admin-dashboard';
      }
      if (name === currentRoute && (nowTs - lastRouteSwitchAt) < ROUTE_DEBOUNCE_MS) return;
      if ((nowTs - lastRouteSwitchAt) < ROUTE_DEBOUNCE_MS) return;
      isRouteTransitioning = true;
      lastRouteSwitchAt = nowTs;

      if (currentRoute === 'code-view' && name !== 'code-view' && name !== 'code-edit') {
        window.currentCodeData = null;
      }
      
      if (currentRoute === 'code-edit' && name !== 'code-edit') {
        window.editOriginalCode = null;
        window.editRewards = [];
      }

      currentRoute = name;
      
      Object.entries(routes).forEach(([k, el]) => {
  
        el?.classList.toggle('route-active', k === name);
      });
      
      navItems.forEach(btn => {
        btn.classList.toggle('active', btn.dataset.route === name);
      });

      if (breadcrumbs) {
        let crumbKey = 'UI_BREADCRUMBS_DASHBOARD';
        if (name === 'player') crumbKey = 'UI_BREADCRUMBS_PLAYER';
        else if (name === 'create-code') crumbKey = 'UI_BREADCRUMBS_CODES';
        else if (name === 'ai-generation') crumbKey = 'UI_BREADCRUMBS_AI_GENERATION';
        else if (name === 'admin-codes') crumbKey = 'UI_BREADCRUMBS_CODES';
        else if (name === 'admin-settings') crumbKey = 'UI_BREADCRUMBS_SETTINGS';
        else if (name === 'code-view') crumbKey = 'UI_BREADCRUMBS_CODES';
        else if (name === 'code-edit') crumbKey = 'UI_BREADCRUMBS_CODES';
        breadcrumbs.setAttribute('data-locale', crumbKey);
        breadcrumbs.textContent = t(crumbKey);
      }

      try { applyLocale(); } catch (_) {}
      switch (name) {
        case 'admin-dashboard':
          Promise.all([loadDashboard(), loadUserPermissions()]);
          break;
        case 'create-code':
          openWizardModal();
          break;
        case 'ai-generation':
          initShadowRoute();
          break;
        case 'admin-codes':
          Promise.all([loadAllCodes(), loadUserPermissions()]);
          break;
        case 'code-view':
          Promise.all([loadCodeView(), loadUserPermissions()]);
          break;
        case 'code-edit':
          Promise.all([loadCodeEdit(), loadUserPermissions()]);
          break;
        case 'admin-settings':
          showSettingsSection('displaySettingsSection');
          loadUserPermissions().then(() => {
            refreshOwnerSettingsIfVisible();
            loadUserList();
          });
          break;
        case 'player':
          loadPlayer();
          break;
        default:
          loadDashboard();
          break;
      }

      isRouteTransitioning = false;
    }
  
    function togglePlayerChrome(isPlayer) {
      document.body.classList.toggle('player-only', !!isPlayer);
    }
  
    async function nuiRet(action, data={}) {
      return new Promise((resolve, reject) => {
        const isSlowAction = /shadow|Shadow|AIChat|createShadow|RuntimeConfig|getRuntimeConfig|saveRuntimeConfig/i.test(action);
        const timeoutDuration = action.includes('Permission') ? 10000 : (isSlowAction ? 35000 : 3000);
        const timeout = setTimeout(() => {
          reject(new Error('Request timeout'));
        }, timeoutDuration);
        
        fetch(`https://${PRN}/${action}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        })
        .then(response => {
          if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
          }
          return response.json();
        })
        .then(result => {
          clearTimeout(timeout);
          resolve(result);
        })
        .catch(error => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    }

    function showAIChatSubsection(subsection) {
      doc.querySelectorAll('.ai-chat-subsection').forEach(sub => sub.classList.add('hidden'));
      const targetSubsection = doc.getElementById(subsection);
      if (targetSubsection) {
        targetSubsection.classList.remove('hidden');
      }
      doc.querySelectorAll('.ai-chat-settings-nav .btn').forEach(btn => {
        btn.classList.remove('btn-primary');
        btn.classList.add('btn-secondary');
      });
      const activeButton = doc.querySelector(`[data-subsection="${subsection}"]`);
      if (activeButton) {
        activeButton.classList.remove('btn-secondary');
        activeButton.classList.add('btn-primary');
      }
      if (subsection === 'chatSettingsSection') {
        loadAIChatSettings();
      }
    }

    async function loadAIChatSettings() {
      try {
        const result = await nuiRet('getAIChatSettings', {});
        if (!result?.success || !result.settings) {
          toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', result?.error || t('UI_SETTINGS_CHAT_LOAD_FAILED') || 'Failed to load chat settings.', 'error');
          return;
        }
        const s = result.settings;
        doc.getElementById('aiChatEnabledToggle').checked = !!s.aiEnabled;
        doc.getElementById('aiChatRateLimit').value = s.rateLimit ?? 0;
        doc.getElementById('aiChatRateLimitWindow').value = s.rateLimitWindow ?? 24;
        doc.getElementById('aiChatTranscriptRetention').value = s.transcriptRetentionDays ?? 31;
        doc.getElementById('aiChatWelcomeMessage').value = s.welcomeMessage || '';
        doc.getElementById('aiChatWebSearchStatus').textContent = s.webSearchEnabled ? (t('UI_SETTINGS_CHAT_ENABLED_STATUS') || 'Enabled') : (t('UI_SETTINGS_CHAT_DISABLED_STATUS') || 'Disabled');
        doc.getElementById('aiChatProviderStatus').textContent = s.aiProvider || '—';
        doc.getElementById('aiChatModelStatus').textContent = s.aiModel || '—';
        aiEnabled = !!s.aiEnabled;
        setupAIVisibility();
      } catch (error) {
        console.error('Failed to load AI chat settings:', error);
      }
    }

    async function saveAIChatSettings() {
      if (!isOwnerUser) return;
      const payload = {
        aiEnabled: !!doc.getElementById('aiChatEnabledToggle')?.checked,
        rateLimit: Number(doc.getElementById('aiChatRateLimit')?.value || 0),
        rateLimitWindow: Number(doc.getElementById('aiChatRateLimitWindow')?.value || 24),
        transcriptRetentionDays: Number(doc.getElementById('aiChatTranscriptRetention')?.value || 31),
        welcomeMessage: doc.getElementById('aiChatWelcomeMessage')?.value || ''
      };
      try {
        const result = await nuiRet('saveAIChatSettings', payload);
        if (result?.success) {
          aiEnabled = !!result.settings?.aiEnabled;
          setupAIVisibility();
          toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', t('UI_SETTINGS_CHAT_SAVED') || 'Chat settings saved.', 'success');
        } else {
          toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', result?.error || t('UI_SETTINGS_CHAT_SAVE_FAILED') || 'Failed to save chat settings.', 'error');
        }
      } catch (error) {
        toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', t('UI_SETTINGS_CHAT_SAVE_FAILED') || 'Failed to save chat settings.', 'error');
      }
    }

    function showRuntimeConfigTab(tab) {
      activeRuntimeConfigTab = tab;
      doc.querySelectorAll('.runtime-config-tab').forEach(el => el.classList.add('hidden'));
      const map = {
        general: 'runtimeConfigGeneral',
        daily: 'runtimeConfigDaily',
        prefilled: 'runtimeConfigPrefilled',
        contentFilter: 'runtimeConfigContentFilter'
      };
      const target = doc.getElementById(map[tab]);
      if (target) target.classList.remove('hidden');
      doc.querySelectorAll('[data-config-tab]').forEach(btn => {
        btn.classList.toggle('btn-primary', btn.dataset.configTab === tab);
        btn.classList.toggle('btn-secondary', btn.dataset.configTab !== tab);
      });
    }

    function renderContentFilterEditor(badWords) {
      const host = doc.getElementById('contentFilterEditor');
      if (!host || !window.RuntimeConfigEditors) return;
      window.RuntimeConfigEditors.renderContentFilterEditor(host, badWords);
    }

    function populateRuntimeConfigForms(data) {
      runtimeConfigCache = data || {};
      const editors = window.RuntimeConfigEditors;
      const general = data.general || {};
      doc.getElementById('cfgDebug').checked = !!general.Debug;
      doc.getElementById('cfgFramework').value = general.Framework || 'qb';
      doc.getElementById('cfgAdminCommand').value = general.AdminCommand || 'adminredeem';
      doc.getElementById('cfgRedeemCommand').value = general.RedeemCommand || 'redeemcode';
      doc.getElementById('cfgMinCustomChar').value = general.mincustomchar ?? 6;
      doc.getElementById('cfgSqlCleanUpDays').value = general.sqlCleanUpDays ?? 14;
      doc.getElementById('cfgDashboardRefresh').value = general.DashboardRefreshInterval ?? 180;
      doc.getElementById('cfgLogsystem').value = general.Logsystem || 'both';

      const daily = data.daily || {};
      doc.getElementById('cfgDailyEnabled').checked = daily.DailyRewardEnabled !== false;
      doc.getElementById('cfgRewardTimes').value = Array.isArray(daily.RewardTimes) ? daily.RewardTimes.join(', ') : '00:00';
      doc.getElementById('cfgDailyUses').value = daily.DailyRewarduses ?? 3;
      doc.getElementById('cfgDailyPerUser').value = daily.DailyRewardperuserlimit ?? 1;
      doc.getElementById('cfgDailyHours').value = daily.DailyRewardhours ?? 24;

      if (editors) {
        const dailyHost = doc.getElementById('dailyRewardsEditor');
        if (dailyHost) editors.renderDailyRewardsEditor(dailyHost, daily.DailyRewards || []);

        const prefilledHost = doc.getElementById('prefilledRewardsEditor');
        if (prefilledHost) {
          editors.renderPrefilledEditor(prefilledHost, {
            PreFilledRewards: (data.prefilled || {}).PreFilledRewards || {},
            AICodeTemplates: (data.prefilled || {}).AICodeTemplates || {}
          });
        }

        renderContentFilterEditor((data.contentFilter || {}).BadWords || {});
      }
    }

    function collectRuntimeConfigPayload(section) {
      if (section === 'general') {
        return {
          Debug: !!doc.getElementById('cfgDebug')?.checked,
          Framework: doc.getElementById('cfgFramework')?.value || 'qb',
          AdminCommand: doc.getElementById('cfgAdminCommand')?.value || 'adminredeem',
          RedeemCommand: doc.getElementById('cfgRedeemCommand')?.value || 'redeemcode',
          mincustomchar: Number(doc.getElementById('cfgMinCustomChar')?.value || 6),
          sqlCleanUpDays: Number(doc.getElementById('cfgSqlCleanUpDays')?.value || 14),
          DashboardRefreshInterval: Number(doc.getElementById('cfgDashboardRefresh')?.value || 180),
          Logsystem: doc.getElementById('cfgLogsystem')?.value || 'both'
        };
      }
      if (section === 'daily') {
        const times = (doc.getElementById('cfgRewardTimes')?.value || '00:00').split(',').map(v => v.trim()).filter(Boolean);
        const dailyHost = doc.getElementById('dailyRewardsEditor');
        return {
          DailyRewardEnabled: !!doc.getElementById('cfgDailyEnabled')?.checked,
          RewardTimes: times.length ? times : ['00:00'],
          DailyRewarduses: Number(doc.getElementById('cfgDailyUses')?.value || 3),
          DailyRewardperuserlimit: Number(doc.getElementById('cfgDailyPerUser')?.value || 1),
          DailyRewardhours: Number(doc.getElementById('cfgDailyHours')?.value || 24),
          DailyRewards: window.RuntimeConfigEditors?.collectDailyRewards(dailyHost) || []
        };
      }
      if (section === 'prefilled') {
        const prefilledHost = doc.getElementById('prefilledRewardsEditor');
        const collected = window.RuntimeConfigEditors?.collectPrefilled(prefilledHost) || {};
        return {
          PreFilledRewards: collected.PreFilledRewards || {},
          AICodeTemplates: collected.AICodeTemplates || {}
        };
      }
      if (section === 'contentFilter') {
        const filterHost = doc.getElementById('contentFilterEditor');
        return window.RuntimeConfigEditors?.collectContentFilter(filterHost) || { BadWords: {} };
      }
      return null;
    }

    async function loadRuntimeConfigTab(tab) {
      showRuntimeConfigTab(tab);
      try {
        const result = await nuiRet('getRuntimeConfig', {});
        if (!result?.success) {
          toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', result?.error || 'Failed to load config.', 'error');
          return;
        }
        populateRuntimeConfigForms(result.data || {});
      } catch (error) {
        console.error('Failed to load runtime config:', error);
        toast(
          t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config',
          error?.message || 'Failed to load config.',
          'error'
        );
      }
    }

    async function saveRuntimeConfigTab() {
      if (!isOwnerUser) return;
      try {
        const payload = collectRuntimeConfigPayload(activeRuntimeConfigTab);
        const result = await nuiRet('saveRuntimeConfig', { section: activeRuntimeConfigTab, payload });
          if (result?.success) {
            window._preFilledRewardsCache = null;
            toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', t('UI_SETTINGS_CONFIG_SAVED') || 'Configuration saved.', 'success');
          if (activeRuntimeConfigTab === 'daily' || activeRuntimeConfigTab === 'general') {
            const cfg = await nuiRet('getServerConfig', {});
            if (cfg && typeof cfg.aiEnabled !== 'undefined') {
              aiEnabled = !!cfg.aiEnabled;
              setupAIVisibility();
            }
          }
          await loadRuntimeConfigTab(activeRuntimeConfigTab);
        } else {
          toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', result?.error || t('UI_SETTINGS_CONFIG_SAVE_FAILED') || 'Failed to save configuration.', 'error');
        }
      } catch (error) {
        toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', error.message || t('UI_SETTINGS_CONFIG_SAVE_FAILED') || 'Failed to save configuration.', 'error');
      }
    }

    async function resetRuntimeConfigTab() {
      if (!isOwnerUser) return;
      try {
        const result = await nuiRet('resetRuntimeConfig', { section: activeRuntimeConfigTab });
        if (result?.success) {
          toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', t('UI_SETTINGS_CONFIG_RESET_DONE') || 'Configuration reset to defaults.', 'success');
          await loadRuntimeConfigTab(activeRuntimeConfigTab);
        } else {
          toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', result?.error || 'Failed to reset configuration.', 'error');
        }
      } catch (error) {
        toast(t('UI_SETTINGS_RUNTIME_CONFIG_TITLE') || 'Server Config', 'Failed to reset configuration.', 'error');
      }
    }
  
    function nui(action, data={}){
      return fetch(`https://${PRN}/${action}`, {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify(data)
      });
    }
  
  
    async function loadDashboard() {
      try {
        await nui('refreshData', {});
      } catch (error) {
        console.error('Failed to request dashboard data:', error);
        toast('Dashboard Error', 'Failed to request dashboard data', 'error');
      }
    }
  
      
  
    async function loadCodeManagement() {
      try {
  
        await loadDashboard();
      } catch (error) {
        console.error('Failed to load code management:', error);
        toast('Code Management Error', 'Failed to load code management data', 'error');
      }
    }
  
    async function loadPlayer() {
      try {
  
      } catch (error) {
        console.error('Error loading player view:', error);
      }
    }

    let shadowConversationHistory = [];
    let currentShadowSessionId = null;
    let pendingShadowAction = null;
    let shadowExecuteInFlight = false;

    function addShadowMessage(message, isUser = false) {
      const host = doc.getElementById('shadowChatMessages');
      if (!host) return;
      const messageDiv = doc.createElement('div');
      messageDiv.className = `ai-message ${isUser ? 'ai-user-message' : 'ai-assistant-message'}`;
      const avatarDiv = doc.createElement('div');
      avatarDiv.className = 'ai-message-avatar';
      avatarDiv.innerHTML = `<i class="fas ${isUser ? 'fa-user' : 'fa-robot'}"></i>`;
      const contentDiv = doc.createElement('div');
      contentDiv.className = 'ai-message-content';
      if (!isUser) {
        const nameTag = doc.createElement('div');
        nameTag.className = 'ai-message-name';
        nameTag.textContent = 'shadow';
        contentDiv.appendChild(nameTag);
      }
      const textDiv = doc.createElement('div');
      textDiv.className = 'ai-message-text';
      textDiv.textContent = message || '';
      contentDiv.appendChild(textDiv);
      messageDiv.appendChild(avatarDiv);
      messageDiv.appendChild(contentDiv);
      const typing = doc.getElementById('shadowTypingIndicator');
      if (typing && typing.parentElement === host) {
        host.insertBefore(messageDiv, typing);
      } else {
        host.appendChild(messageDiv);
      }
      scrollShadowChatToBottom();
      shadowConversationHistory.push({ role: isUser ? 'user' : 'assistant', content: message || '' });
    }

    function tryParseShadowAction(message) {
      if (!message || typeof message !== 'string') return null;
      const fenced = message.match(/```json\s*([\s\S]*?)```/i);
      const candidates = [];
      if (fenced) candidates.push(fenced[1]);
      const trimmed = message.trim();
      if (trimmed.startsWith('{')) candidates.push(trimmed);
      const inline = message.match(/\{[\s\S]*"action"[\s\S]*\}/);
      if (inline) candidates.push(inline[0]);
      for (const raw of candidates) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed && parsed.action && parsed.payload) return parsed;
        } catch (_) {}
      }
      return null;
    }

    function stripShadowActionJson(message) {
      if (!message || typeof message !== 'string') return '';
      let cleaned = message.replace(/```json[\s\S]*?```/gi, '').trim();
      if (cleaned.startsWith('{') && cleaned.includes('"action"')) return '';
      return cleaned;
    }

    function getShadowThinkingStatus(message, context = {}) {
      const lower = (message || '').toLowerCase();
      const action = context.action || '';

      if (action === 'create') return 'Creating code in your database…';
      if (action === 'update') return 'Applying code changes…';

      if (/create|new code|make .+ code|want a code|want a new|need a code|with the prefix|prefix is/.test(lower)
        || ((/i want|i need/.test(lower)) && lower.includes('code'))) {
        return 'Drafting a new redeem code…';
      }
      if (/update|edit code/.test(lower)) {
        return 'Preparing your code update…';
      }
      if (/lookup|find code|details for code/.test(lower)) {
        return 'Looking up that code in your database…';
      }
      if ((/active|expired|not expired|all code|list code|show code|search code|how many code/.test(lower))
        && lower.includes('code')) {
        return 'Searching your redeem codes…';
      }
      if (/weather|forecast|temperature/.test(lower)) {
        return 'Checking the weather…';
      }
      if (/news|score|price|stock|who won|when is/.test(lower)) {
        return 'Searching the web for an answer…';
      }
      if (lower.includes('code') || lower.includes('redeem')) {
        return 'Working on your redeem request…';
      }
      if (/how are you|hello|hi |hey /.test(lower)) {
        return 'Thinking of a reply…';
      }
      return 'Thinking…';
    }

    function setShadowThinkingStatus(message, context = {}) {
      const typing = doc.getElementById('shadowTypingIndicator');
      const statusEl = doc.getElementById('shadowThinkingStatus');
      const text = getShadowThinkingStatus(message, context);
      if (statusEl) statusEl.textContent = text;
      if (typing) typing.classList.remove('hidden');
      scrollShadowChatToBottom();
    }

    function clearShadowThinkingStatus() {
      const typing = doc.getElementById('shadowTypingIndicator');
      const statusEl = doc.getElementById('shadowThinkingStatus');
      if (statusEl) statusEl.textContent = '';
      if (typing) typing.classList.add('hidden');
    }

    function formatShadowActionSummary(actionObject) {
      const action = actionObject?.action;
      const payload = actionObject?.payload || {};
      if (actionObject?.summary) return actionObject.summary;
      if (action === 'create') {
        const rewards = (payload.rewards || []).map((r) => {
          if (r.type === 'money' || r.money) return `${r.amount || 0} money`;
          if (r.type === 'vehicle' || r.vehicle || r.model) return `1 ${r.name || r.model || r.vehicle}`;
          return `${r.amount || 1}x ${r.name || r.item || 'item'}`;
        }).join(', ');
        return `Ready to create code "${payload.code}" — ${payload.uses || 1} use(s), ${payload.perUserLimit || 1} per player, ${payload.expiryDays || 0} day expiry${rewards ? `, rewards: ${rewards}` : ''}. Confirm below?`;
      }
      if (action === 'update') {
        return `Ready to update code "${payload.originalCode}". Confirm below?`;
      }
      return `${action || 'Action'} ready — confirm below?`;
    }

    function isShadowConfirmMessage(message) {
      if (!message || typeof message !== 'string') return false;
      const normalized = message.trim().toLowerCase();
      if (!normalized) return false;
      if (/\b(no|nah|nope|don't|do not|cancel|stop|wait)\b/.test(normalized)) return false;
      return /\b(yes|yeah|yep|yup|sure|ok|okay|confirm|do it|go ahead|please do|sounds good|create it|update it)\b/.test(normalized);
    }

    function renderShadowResultCard(result, action) {
      const host = doc.getElementById('shadowChatMessages');
      if (!host || !result) return;

      const messageDiv = doc.createElement('div');
      messageDiv.className = `ai-message ai-assistant-message shadow-result-message ${result.success ? 'shadow-result-success' : 'shadow-result-failure'}`;

      const avatarDiv = doc.createElement('div');
      avatarDiv.className = 'ai-message-avatar';
      avatarDiv.innerHTML = '<i class="fas fa-robot"></i>';

      const contentDiv = doc.createElement('div');
      contentDiv.className = 'ai-message-content';

      const nameTag = doc.createElement('div');
      nameTag.className = 'ai-message-name';
      nameTag.textContent = 'shadow';

      const titleDiv = doc.createElement('div');
      titleDiv.className = 'shadow-result-title';
      titleDiv.textContent = result.success
        ? `${action === 'update' ? 'Update' : 'Create'} completed`
        : `${action === 'update' ? 'Update' : 'Create'} failed`;

      const textDiv = doc.createElement('div');
      textDiv.className = 'ai-message-text';
      textDiv.textContent = result.message || result.error || 'Action completed.';

      contentDiv.appendChild(nameTag);
      contentDiv.appendChild(titleDiv);
      contentDiv.appendChild(textDiv);
      messageDiv.appendChild(avatarDiv);
      messageDiv.appendChild(contentDiv);

      const typing = doc.getElementById('shadowTypingIndicator');
      if (typing && typing.parentElement === host) {
        host.insertBefore(messageDiv, typing);
      } else {
        host.appendChild(messageDiv);
      }
      scrollShadowChatToBottom();
    }

    function renderShadowActionCard(actionObject) {
      const host = doc.getElementById('shadowChatMessages');
      if (!host || !actionObject) return;

      const action = actionObject.action;
      const payload = actionObject.payload || {};
      const summary = formatShadowActionSummary(actionObject);

      const messageDiv = doc.createElement('div');
      messageDiv.className = 'ai-message ai-assistant-message shadow-action-message';
      messageDiv.dataset.shadowAction = 'true';

      const avatarDiv = doc.createElement('div');
      avatarDiv.className = 'ai-message-avatar';
      avatarDiv.innerHTML = '<i class="fas fa-robot"></i>';

      const contentDiv = doc.createElement('div');
      contentDiv.className = 'ai-message-content';

      const nameTag = doc.createElement('div');
      nameTag.className = 'ai-message-name';
      nameTag.textContent = 'shadow';

      const textDiv = doc.createElement('div');
      textDiv.className = 'ai-message-text';
      textDiv.textContent = summary;

      const buttonsDiv = doc.createElement('div');
      buttonsDiv.className = 'shadow-action-buttons shadow-action-buttons-inline';

      const confirmBtn = doc.createElement('button');
      confirmBtn.className = 'btn btn-primary';
      confirmBtn.textContent = action === 'update' ? 'Confirm & Update' : 'Confirm & Create';

      const dismissBtn = doc.createElement('button');
      dismissBtn.className = 'btn btn-secondary';
      dismissBtn.textContent = 'Keep Chatting';

      buttonsDiv.appendChild(confirmBtn);
      buttonsDiv.appendChild(dismissBtn);
      contentDiv.appendChild(nameTag);
      contentDiv.appendChild(textDiv);
      contentDiv.appendChild(buttonsDiv);
      messageDiv.appendChild(avatarDiv);
      messageDiv.appendChild(contentDiv);

      const typing = doc.getElementById('shadowTypingIndicator');
      if (typing && typing.parentElement === host) {
        host.insertBefore(messageDiv, typing);
      } else {
        host.appendChild(messageDiv);
      }
      scrollShadowChatToBottom();
      shadowConversationHistory.push({ role: 'assistant', content: summary });

      confirmBtn.addEventListener('click', async () => {
        if (shadowExecuteInFlight) return;
        shadowExecuteInFlight = true;
        confirmBtn.disabled = true;
        dismissBtn.disabled = true;
        setShadowThinkingStatus('', { action });
        try {
          const result = await nuiRet('shadowExecuteAction', {
            action,
            payload,
            sessionId: currentShadowSessionId
          });
          clearShadowThinkingStatus();
          if (result && result.success) {
            renderShadowResultCard(result, action);
            messageDiv.remove();
            pendingShadowAction = null;
            refreshAll();
          } else {
            renderShadowResultCard(result || { success: false, error: 'Action failed.' }, action);
            confirmBtn.disabled = false;
            dismissBtn.disabled = false;
          }
        } catch (error) {
          clearShadowThinkingStatus();
          renderShadowResultCard({ success: false, error: 'Action failed due to a connection error.' }, action);
          confirmBtn.disabled = false;
          dismissBtn.disabled = false;
        } finally {
          shadowExecuteInFlight = false;
        }
      });

      dismissBtn.addEventListener('click', () => {
        messageDiv.remove();
        pendingShadowAction = null;
      });
    }

    function scrollShadowChatToBottom() {
      const host = doc.getElementById('shadowChatMessages');
      if (host) host.scrollTop = host.scrollHeight;
    }

    async function sendShadowMessage(message) {
      if (!message || !message.trim()) return;
      const confirmPending = pendingShadowAction && isShadowConfirmMessage(message);
      if (confirmPending && shadowExecuteInFlight) return;
      addShadowMessage(message, true);
      setShadowThinkingStatus(message, confirmPending ? { action: pendingShadowAction.action } : {});
      if (confirmPending) shadowExecuteInFlight = true;
      try {
        const response = await nuiRet('shadowChatMessage', {
          message,
          conversationHistory: currentShadowSessionId ? [] : shadowConversationHistory,
          sessionId: currentShadowSessionId,
          pendingAction: pendingShadowAction,
          confirmPendingAction: confirmPending
        });
        clearShadowThinkingStatus();
        if (!response || !response.success) {
          addShadowMessage(response?.error || 'Shadow could not process that request.', false);
          return;
        }
        if (response.sessionId) currentShadowSessionId = response.sessionId;
        if (response.actionResult) {
          const action = pendingShadowAction?.action || response.actionResult.action;
          renderShadowResultCard(response.actionResult, action);
          if (response.actionResult.success) {
            pendingShadowAction = null;
            doc.getElementById('shadowChatMessages')
              ?.querySelectorAll('.shadow-action-message')
              .forEach((el) => el.remove());
            refreshAll();
          }
          return;
        }
        const actionObject = response.actionProposal || null;
        if (actionObject && (actionObject.action === 'create' || actionObject.action === 'update')) {
          pendingShadowAction = actionObject;
          const messagesHost = doc.getElementById('shadowChatMessages');
          messagesHost?.querySelectorAll('.shadow-action-message').forEach((el) => el.remove());
          renderShadowActionCard(actionObject);
        } else {
          pendingShadowAction = null;
          addShadowMessage(response.message || 'Done.', false);
        }
      } catch (error) {
        clearShadowThinkingStatus();
        const detail = error?.message ? ` (${error.message})` : '';
        addShadowMessage(`Shadow encountered a connection error${detail}.`, false);
      } finally {
        if (confirmPending) shadowExecuteInFlight = false;
      }
    }

    async function initShadowRoute() {
      const rulesPage = doc.getElementById('shadowRulesPage');
      const chatPage = doc.getElementById('shadowChatPage');
      if (rulesPage) rulesPage.classList.remove('hidden');
      if (chatPage) chatPage.classList.add('hidden');
      shadowConversationHistory = [];
      pendingShadowAction = null;
      shadowExecuteInFlight = false;
    }
  
    async function loadCodeView() {
      try {
        if (window.userPermissions) {
          updatePermissionsUI(window.userPermissions);
        }
      } catch (error) {
        console.error('Error loading code view:', error);
      }
    }
  
    async function loadCodeEdit() {
      try {
        if (window.userPermissions) {
          updatePermissionsUI(window.userPermissions);
        }
        setupEditFormEventListeners();
      } catch (error) {
        console.error('Error loading code edit:', error);
      }
    }
  
    function setupEditFormEventListeners() {
      if (window.editListenersBound) return;
      window.editListenersBound = true;
  
      doc.getElementById('backToView')?.addEventListener('click', async () => {
        const code = doc.getElementById('editCode')?.value || window.editOriginalCode || '';
        if (code) {
          showRoute('code-view');
          await loadCodeDetails(code);
        } else {
          showRoute('code-view');
        }
      });
  
  
      doc.getElementById('saveEdit')?.addEventListener('click', saveEditChanges);
  
  
      doc.getElementById('resetEdit')?.addEventListener('click', () => {
  
        const code = doc.getElementById('editCode')?.value;
        if (code) {
          openEditPage(code);
        }
      });
  
  
      doc.getElementById('deleteEdit')?.addEventListener('click', async () => {
        const code = doc.getElementById('editCode')?.value;
        if (code) {
  
          try {
            const codeData = await nuiRet('getCodeDetails', { code: code });
            if (codeData && codeData.success) {
              window.currentCodeData = codeData.data;
  
            }
          } catch (error) {
            console.error('Failed to get code data for delete modal:', error);
          }
          deleteCode(code);
        }
      });
  
  
      doc.getElementById('addEditReward')?.addEventListener('click', addEditReward);
    }
  
    async function loadAdminSettings() {
      try {
        await loadUserPermissions();
        refreshOwnerSettingsIfVisible();
        setTimeout(() => {
          if (currentRoute === 'admin-settings') {
            loadUserList();
          }
        }, 200);
      } catch (error) {
        console.error('Error loading admin settings:', error);
      }
    }
  
    async function loadAdminCodes() {
      try {
        const codes = await nuiRet('getAllCodesWithDetails', {});
        if (codes && codes.success && codes.data) {
          displayAllCodes(codes.data);
        } else {
          console.error('Failed to load codes:', codes);
        }
      } catch (error) {
        console.error('Error loading admin codes:', error);
      }
    }
  
    async function loadAdminDashboard() {
      try {
        await loadDashboard();
      } catch (error) {
        console.error('Error loading admin dashboard:', error);
      }
    }
  
    async function loadUserPermissions(force = false) {
      try {
        if (!force && window.userPermissions?.role && typeof window.userPermissions.level === 'number') {
          updatePermissionsUI(window.userPermissions);
          return;
        }

        const response = await nuiRet('getUserPermissions', {});
        
        if (response && response.role && typeof response.level === 'number') {
          window.userPermissions = response;
          updatePermissionsUI(response);
        } else {
          window.userPermissions = { role: 'staff', level: 1 };
          updatePermissionsUI({ role: 'staff', level: 1 });
        }
      } catch (error) {
        console.error('Failed to load user permissions:', error);
        window.userPermissions = { role: 'staff', level: 1 };
        updatePermissionsUI({ role: 'staff', level: 1 });
      }
    }
  
    async function loadUserList() {
      try {
        const response = await nuiRet('getAllUserPermissions', {});
        
  
        let users = [];
        if (response && Array.isArray(response)) {
          users = response;
        } else if (response && response.success && Array.isArray(response.data)) {
          users = response.data;
        } else if (response && response.data && Array.isArray(response.data)) {
          users = response.data;
        } else if (response && typeof response === 'object') {
  
          users = [];
        }
        
        
        if (users && Array.isArray(users) && users.length > 0) {
          
  
          window.allUsers = users;
          
  
          const onlineUsers = users.filter(user => user.online);
          const allUsers = users;
          
  
          const onlinePlayers = doc.getElementById('onlinePlayers');
          if (onlinePlayers) {
            if (onlineUsers.length > 0) {
              let html = '';
              onlineUsers.forEach(player => {
                html += `<div class="user-item">${escapeHtml(player.name)} (ID: ${escapeHtml(player.source || 'N/A')})</div>`;
              });
              onlinePlayers.innerHTML = html;
        } else {
              onlinePlayers.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_NO_PLAYERS_ONLINE'))}</p>`;
            }
          }
          
  
          const userList = doc.getElementById('userList');
          if (userList) {
            if (allUsers.length > 0) {
              let html = '';
              allUsers.forEach(user => {
                const onlineStatus = user.online ? '<span class="status-online">●</span>' : '<span class="status-offline">●</span>';
                const canEdit = user.role !== 'owner' || (window.userPermissions && window.userPermissions.role === 'owner');
                const canDelete = user.role !== 'owner' || (window.userPermissions && window.userPermissions.role === 'owner');
                
                html += `
                  <div class="user-item">
                    <div class="user-info">
                      <span class="user-status">${onlineStatus}</span>
                      <span class="user-name">${user.name}</span>
                      <span class="user-role">${user.role}</span>
                      <span class="user-level">(Level: ${user.level})</span>
                    </div>
                    <div class="user-actions">
                      ${canEdit ? `<button class="btn btn-xs btn-secondary" onclick="editUserRole('${user.identifier}', '${user.name}', '${user.role}')">Edit</button>` : ''}
                      ${canDelete ? `<button class="btn btn-xs btn-danger" onclick="showDeleteUserModal('${user.identifier}')">Delete</button>` : ''}
                    </div>
                  </div>
                `;
              });
              userList.innerHTML = html;
            } else {
              userList.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_NO_USERS_FOUND'))}</p>`;
            }
          }
        } else {


          const onlinePlayers = doc.getElementById('onlinePlayers');
          const userList = doc.getElementById('userList');
          if (onlinePlayers) onlinePlayers.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_NO_PLAYERS_ONLINE'))}</p>`;
          if (userList) userList.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_NO_USERS_FOUND'))}</p>`;
        }
      } catch (error) {
        console.error('Failed to load user list:', error);

        const onlinePlayers = doc.getElementById('onlinePlayers');
        const userList = doc.getElementById('userList');
        if (onlinePlayers) onlinePlayers.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_ERROR_LOADING_ONLINE'))}</p>`;
        if (userList) userList.innerHTML = `<p>${escapeHtml(t('UI_PERMISSIONS_ERROR_LOADING_ONLINE'))}</p>`;
      }
    }
  
  
    window.editUserRole = function(identifier, userName, currentRole) {
  
      window.editingUser = { identifier, userName, currentRole };
      
  
      setText('editRoleUserName', userName);
      setText('editRoleCurrentRole', currentRole);
      
  
      const roleSelect = doc.getElementById('editRoleSelect');
      if (roleSelect) {
        roleSelect.value = currentRole;
      }
      
      const modal = doc.getElementById('editRoleModal');
      if (modal) {
        modal.classList.remove('hidden');
      }
    }
  
  
    async function updateUserRole() {
      try {
        const { identifier, userName, currentRole } = window.editingUser;
        const newRole = doc.getElementById('editRoleSelect').value;
        
        if (!newRole || newRole === currentRole) {
          hideEditRoleModal();
          return;
        }
        
        if (!['staff', 'manager', 'owner'].includes(newRole.toLowerCase())) {
          toast('Error', 'Invalid role. Must be staff, manager, or owner.', 'error');
          return;
        }
        
        if (!identifier) {
          toast('Error', 'User identifier not found', 'error');
          return;
        }
        
        // Update user role using identifier (works for both online and offline users)
        const result = await nuiRet('updateUserPermission', { identifier: identifier, newRole: newRole.toLowerCase() });
        
        if (result && result.success) {
          toast('Success', `Successfully updated ${userName}'s role to ${newRole}`, 'success');
          loadUserList();
          hideEditRoleModal();
        } else {
          toast('Error', result?.message || 'Failed to update user role', 'error');
        }
      } catch (error) {
        console.error('Error updating user role:', error);
        toast('Error', 'Error updating user role', 'error');
      }
    }
  
  
    function hideEditRoleModal() {
      const modal = doc.getElementById('editRoleModal');
      if (modal) {
        modal.classList.add('hidden');
      }
      window.editingUser = null;
    }
  
    window.deleteUser = async function(identifier, userName) {
      try {
        const result = await nuiRet('deleteUser', { identifier });
        if (result && result.success) {
          toast('Success', `Successfully deleted ${userName}`, 'success');
          await loadUserList();
        } else {
          toast('Error', result?.message || `Failed to delete ${userName}`, 'error');
        }
      } catch (error) {
        console.error('Error deleting user:', error);
        toast('Error', 'Error deleting user', 'error');
      }
    }
  
    async function refreshAll() {
      try {
        if (currentRoute === 'admin-dashboard') {
          await loadDashboard();
        } else if (currentRoute === 'admin-codes') {
          await loadAllCodes();
        }

      } catch (error) {
        console.error('Failed to refresh:', error);
        toast('Refresh Failed', 'Could not refresh data', 'error');
      }
    }
  
    function formatDate(dateString) {
      if (!dateString || dateString === 'N/A') return 'Unknown';
      
      try {
        if (typeof dateString === 'string' && /^\d+$/.test(dateString)) {
          const date = new Date(parseInt(dateString));
          return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
        }
        
        const date = new Date(dateString);
        if (isNaN(date.getTime())) return 'Invalid Date';
        
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
      } catch (error) {
        return 'Invalid Date';
      }
    }
  
    async function loadRecentActivity() {
      // Codes arrive via allDashboardData / codesData push from server
    }
  
    function updateRecentActivity(codes) {
      if (!codes) return;
      
      try {
        const list = doc.getElementById('recentList');
        if (!list) return;
        
        list.innerHTML = '';
        
  
        const allRecentData = [];
        const codesArray = Array.isArray(codes) ? codes : (codes.success && codes.data ? codes.data : []);
        
  
        
        codesArray.forEach(codeData => {
          const code = codeData.code || 'Unknown';
          const uses = codeData.uses || 0;
          const unlimited = codeData.unlimited || false;
          let status = codeData.status || "Active";
          let createdBy = codeData.created_by || "Unknown";
          let created = codeData.created_at || "N/A";
          let rawExp = codeData.expiry || "Never";
          
  
          
  
          let isExpired = false;
          if (rawExp && rawExp !== 'Never') {
            const expiryTime = new Date(rawExp).getTime();
            if (!Number.isNaN(expiryTime)) {
              isExpired = expiryTime < Date.now();
            }
          }
          
          
          let cardStatus = 'active';
          let displayStatus = 'ACTIVE';
          
          if (isExpired) {
            cardStatus = 'expired';
            displayStatus = unlimited ? 'EXPIRED (UNLIMITED)' : 'EXPIRED';
          } else if (unlimited) {
            cardStatus = 'unlimited';
            displayStatus = 'ACTIVE (UNLIMITED)';
          } else if (uses <= 0) {
            cardStatus = 'full';
            displayStatus = 'REDEEMED';
          } else {
            cardStatus = 'active';
            displayStatus = 'ACTIVE';
          }
          
  
          
          const html = `
            <li class="recent-activity-item" data-status="${cardStatus}" data-code="${escapeHtml(code)}">
              <div class="recent-activity-content">
                <div class="recent-activity-code">${escapeHtml(code)}</div>
                <div class="recent-activity-meta">
                  <span>${t('UI_CREATED_BY')}: ${escapeHtml(createdBy)}</span>
                  <span>•</span>
                  <span>${formatDate(created)}</span>
                </div>
              </div>
              <div class="recent-activity-uses">
                ${unlimited ? '' : `<span>Uses:</span><div class="recent-activity-uses-count">${uses}</div>`}
                <div class="recent-activity-status">${displayStatus}</div>
            </div>
            </li>
          `;
          
  
          allRecentData.push({
            code,
            uses: parseInt(uses) || 0,
            status: displayStatus,
            html,
            isExpired,
            createdBy: createdBy || 'Unknown',
            created: created || 'Unknown',
            expiry: rawExp
          });
        });

        allRecentData.forEach(item => {
          const li = doc.createElement('li');
          li.innerHTML = item.html;
          list.appendChild(li);
        });
        
  
        list.querySelectorAll('.recent-activity-item').forEach(item => {
          item.addEventListener('click', (e) => {
            const code = item.getAttribute('data-code');
            if (code) {
  
              viewCode(code);
            }
          });
        });
      } catch (error) {
        console.error('Failed to load recent activity:', error);
      }
    }
  
  
    function parseDateToTimestamp(dateString) {
      if (!dateString || dateString === 'Unknown' || dateString === 'N/A') {
        return 0;
      }
      
      if (/^\d+(\.0)?$/.test(dateString)) {
        const n = Math.floor(parseFloat(dateString));
        return n < 1e12 ? n * 1000 : n;
      }
      const timestamp = new Date(dateString).getTime();
      return Number.isNaN(timestamp) ? 0 : timestamp;
    }
  
  
    function formatDateForDisplay(dateString) {
      if (!dateString || dateString === 'Unknown' || dateString === 'N/A' || dateString === 'Never') {
        return dateString;
      }
      
      let timestamp;
      
      if (/^\d+(\.0)?$/.test(dateString)) {
        const n = Math.floor(parseFloat(dateString));
        timestamp = n < 1e12 ? n * 1000 : n;
      } else {
        timestamp = new Date(dateString).getTime();
      }
      
      if (Number.isNaN(timestamp) || timestamp === 0) {
        return dateString;
      }
      
      const date = new Date(timestamp);
      const day = date.getDate().toString().padStart(2, '0');
      const month = (date.getMonth() + 1).toString().padStart(2, '0');
      const year = date.getFullYear().toString().slice(-2);
      const hours = date.getHours().toString().padStart(2, '0');
      const minutes = date.getMinutes().toString().padStart(2, '0');
      
      return `${day}:${month}:${year} ${hours}:${minutes}`;
    }
  
    let currentWizardStep = 1;
    let wizardRewards = [];
    let selectedTemplate = null;
  
    function openWizardModal() {
      const wizardModal = doc.getElementById('wizardModal');
      if (wizardModal) {
        wizardModal.classList.remove('hidden');

        try { applyLocale(); } catch (_) {}

        resetWizard();
        updateWizardNavigation();

        populateWizardTemplates();
        populateRewardCategories();
      }
    }
  
    function hideWizardModal() {
      const wizardModal = doc.getElementById('wizardModal');
      if (wizardModal) {
        wizardModal.classList.add('hidden');
        resetWizard();
  
        showRoute('admin-dashboard');
      }
    }
  
    function resetWizard() {
      currentWizardStep = 1;
      wizardRewards = [];
      selectedTemplate = null;
      
  
      const wizardCustomCode = doc.getElementById('wizardCustomCode');
      const wizardUses = doc.getElementById('wizardUses');
      const wizardPerUser = doc.getElementById('wizardPerUser');
      const relativeHours = doc.getElementById('relativeHours');
      const specificExpiry = doc.getElementById('specificExpiry');
      const templateName = doc.getElementById('templateName');
      const wizardRewardName = doc.getElementById('wizardRewardName');
      const wizardRewardLabel = doc.getElementById('wizardRewardLabel');
      const wizardRewardAmount = doc.getElementById('wizardRewardAmount');
      if (wizardCustomCode) wizardCustomCode.value = '';
      if (wizardUses) wizardUses.value = '1';
      if (wizardPerUser) wizardPerUser.value = '1';
      if (relativeHours) relativeHours.value = '24';
      if (specificExpiry) specificExpiry.value = '';
      if (templateName) templateName.value = '';
      if (wizardRewardName) wizardRewardName.value = '';
      if (wizardRewardLabel) wizardRewardLabel.value = '';
      if (wizardRewardAmount) {
        wizardRewardAmount.value = '1';
        wizardRewardAmount.style.display = '';
      }
      
      doc.querySelectorAll('.expiry-btn').forEach(btn => btn.classList.remove('active'));
      const neverExpiryBtn = doc.querySelector('.expiry-btn[data-expiry="never"]');
      if (neverExpiryBtn) neverExpiryBtn.classList.add('active');
      
  
      doc.querySelectorAll('.expiry-section').forEach(section => section.classList.add('hidden'));
      

      const wizardRestrictToPlayerEnabled = doc.getElementById('wizardRestrictToPlayerEnabled');
      const wizardPlayerRestrictionSection = doc.getElementById('wizardPlayerRestrictionSection');
      const wizardPlayerIdentifierType = doc.getElementById('wizardPlayerIdentifierType');
      const wizardPlayerIdentifierValue = doc.getElementById('wizardPlayerIdentifierValue');
      if (wizardRestrictToPlayerEnabled) wizardRestrictToPlayerEnabled.checked = false;
      if (wizardPlayerRestrictionSection) wizardPlayerRestrictionSection.classList.add('hidden');
      if (wizardPlayerIdentifierType) wizardPlayerIdentifierType.value = 'citizenid';
      if (wizardPlayerIdentifierValue) wizardPlayerIdentifierValue.value = '';

      const wizardRewardType = doc.getElementById('wizardRewardType');
      if (wizardRewardType) wizardRewardType.value = 'item';
      syncManualRewardFields('wizard');

      if (wizardUses) {
        wizardUses.addEventListener('input', updateWizardSummary);
        wizardUses.addEventListener('change', updateWizardSummary);
      }
      if (wizardPerUser) {
        wizardPerUser.addEventListener('input', updateWizardSummary);
        wizardPerUser.addEventListener('change', updateWizardSummary);
      }

      doc.querySelectorAll('.template-card').forEach(card => card.classList.remove('selected'));

      const wizardTimeRestrictionsEnabled = doc.getElementById('wizardTimeRestrictionsEnabled');
      const wizardTimeRestrictionsSection = doc.getElementById('wizardTimeRestrictionsSection');
      const wizardTimeRestrictionsMessage = doc.getElementById('wizardTimeRestrictionsMessage');
      const wizardCycleBasedLimit = doc.getElementById('wizardCycleBasedLimit');
      
      if (wizardTimeRestrictionsEnabled) {
        wizardTimeRestrictionsEnabled.classList.remove('selected');
      }
      if (wizardTimeRestrictionsSection) {
        wizardTimeRestrictionsSection.classList.add('hidden');
        wizardTimeRestrictionsSection.style.display = 'none';
      }
      if (wizardTimeRestrictionsMessage) wizardTimeRestrictionsMessage.value = '';
      if (wizardCycleBasedLimit) wizardCycleBasedLimit.checked = false;

      doc.querySelectorAll('.restriction-option').forEach(option => option.classList.remove('active'));
      const dailyHoursOption = doc.querySelector('.restriction-option[data-type="daily_hours"]');
      if (dailyHoursOption) dailyHoursOption.classList.add('active');

      doc.querySelectorAll('.restriction-type-section').forEach(section => {
        section.classList.add('hidden');
        section.style.display = 'none';
      });
      const wizardDailyHoursSection = doc.getElementById('wizardDailyHoursSection');
      if (wizardDailyHoursSection) {
        wizardDailyHoursSection.classList.remove('hidden');
        wizardDailyHoursSection.style.display = 'block';
      }

      const wizardStartHour = doc.getElementById('wizardStartHour');
      const wizardEndHour = doc.getElementById('wizardEndHour');
      if (wizardStartHour) wizardStartHour.value = '09:00';
      if (wizardEndHour) wizardEndHour.value = '17:00';

      doc.querySelectorAll('#wizardWeeklyDaysSection input[type="checkbox"]').forEach(checkbox => {
        checkbox.checked = false;
      });

      doc.querySelectorAll('#wizardSpecificDatesSection input[type="date"]').forEach(input => {
        input.value = '';
      });

      const wizardRecurringType = doc.getElementById('wizardRecurringType');
      const wizardRecurringPattern = doc.getElementById('wizardRecurringPattern');
      if (wizardRecurringType) wizardRecurringType.value = 'daily';
      if (wizardRecurringPattern) wizardRecurringPattern.value = '';
      
      updateWizardSteps();
      updateWizardNavigation();
      clearWizardRewards();
      updateWizardSummary();
    }
  
    function updateWizardSteps() {
      const steps = doc.querySelectorAll('.wizard-step-content');
      const stepIndicators = doc.querySelectorAll('.step');
      
      steps.forEach((step, index) => {
        step.classList.toggle('active', index + 1 === currentWizardStep);
      });
      
      stepIndicators.forEach((indicator, index) => {
        const stepNumber = index + 1;
        indicator.classList.toggle('active', stepNumber === currentWizardStep);
        indicator.classList.toggle('completed', stepNumber < currentWizardStep);
      });
    }
  
    function updateWizardNavigation() {
      const prevBtn = doc.getElementById('wizardPrev');
      const nextBtn = doc.getElementById('wizardNext');
      const generateBtn = doc.getElementById('wizardGenerate');
      
      if (prevBtn) prevBtn.disabled = currentWizardStep === 1;
      if (nextBtn) nextBtn.style.display = currentWizardStep === 5 ? 'none' : 'block';
      if (generateBtn) generateBtn.style.display = currentWizardStep === 5 ? 'block' : 'none';
    }
  
    function wizardPreviousStep() {
      if (currentWizardStep > 1) {
        currentWizardStep--;
        updateWizardSteps();
        updateWizardNavigation();
      }
    }
  
    async function wizardNextStep() {
      if (currentWizardStep < 5) {
        if (validateWizardStep(currentWizardStep)) {

          if (currentWizardStep === 1) {
            const code = doc.getElementById('wizardCustomCode')?.value?.trim() || '';
            
            if (code) {

              const nextBtn = doc.getElementById('wizardNextBtn');
              const originalText = nextBtn?.textContent;
              if (nextBtn) {
                nextBtn.textContent = 'Validating...';
                nextBtn.disabled = true;
              }
              
              try {
                const response = await nuiRet('checkCodeName', { codeName: code });
                if (response && !response.valid) {
                  const errorMessage = response.issues ? response.issues.join(', ') : 'Invalid code name';
                  toast('Code Validation Error', errorMessage, 'error');
                  return;
                }
              } catch (error) {
                console.error('Error checking code name:', error);

              } finally {

                if (nextBtn) {
                  nextBtn.textContent = originalText;
                  nextBtn.disabled = false;
                }
              }
            }
          }
          
          currentWizardStep++;
          updateWizardSteps();
          updateWizardNavigation();
          
          if (currentWizardStep === 5) {
            updateWizardSummary();
          }
        }
      }
    }
  
    function validateWizardStep(step) {
      switch (step) {
        case 1:
          const code = doc.getElementById('wizardCustomCode')?.value?.trim() || '';
          
          if (!code) {
            toast('Validation Error', 'Please enter a code', 'error');
            return false;
          }
          return true;
          
        case 2:
          const activeExpiryBtn = doc.querySelector('.expiry-btn.active');
          if (!activeExpiryBtn) {
            toast('Validation Error', 'Please select an expiry method', 'error');
            return false;
          }
          
          const expiryMethod = activeExpiryBtn.dataset.expiry;
          if (expiryMethod === 'relative') {
            const hours = parseInt(doc.getElementById('relativeHours')?.value || '0');
            if (hours <= 0) {
              toast('Validation Error', 'Please enter a valid number of hours', 'error');
              return false;
            }
          } else if (expiryMethod === 'specific') {
            const date = doc.getElementById('specificExpiry')?.value;
            if (!date) {
              toast('Validation Error', 'Please select an expiry date', 'error');
              return false;
            }
          }
          const restrictEnabled = doc.getElementById('wizardRestrictToPlayerEnabled')?.checked === true;
          if (restrictEnabled) {
            const identifierType = doc.getElementById('wizardPlayerIdentifierType')?.value?.trim();
            const identifierValue = doc.getElementById('wizardPlayerIdentifierValue')?.value?.trim();
            if (!identifierType || !identifierValue) {
              toast('Validation Error', 'Please provide identifier type and value for player restriction', 'error');
              return false;
            }
          }
          return true;
          
        case 3:

          return true;
          
        case 4:

          if (wizardRewards.length === 0) {
            toast('Validation Error', 'Please add at least one reward', 'error');
            return false;
          }
          return true;
          
        case 5:

          return true;
          
        default:
          return true;
      }
    }
  
    function setupWizardSelectors() {
      const wizardRestrictToPlayerEnabled = doc.getElementById('wizardRestrictToPlayerEnabled');
      const wizardPlayerRestrictionSection = doc.getElementById('wizardPlayerRestrictionSection');
      if (wizardRestrictToPlayerEnabled && wizardPlayerRestrictionSection) {
        wizardRestrictToPlayerEnabled.addEventListener('change', () => {
          wizardPlayerRestrictionSection.classList.toggle('hidden', !wizardRestrictToPlayerEnabled.checked);
          updateWizardSummary();
        });
      }

      const wizardPlayerIdentifierType = doc.getElementById('wizardPlayerIdentifierType');
      const wizardPlayerIdentifierValue = doc.getElementById('wizardPlayerIdentifierValue');
      wizardPlayerIdentifierType?.addEventListener('change', updateWizardSummary);
      wizardPlayerIdentifierValue?.addEventListener('input', updateWizardSummary);


      const timeRestrictionsButton = doc.getElementById('wizardTimeRestrictionsEnabled');
      const timeRestrictionsSection = doc.getElementById('wizardTimeRestrictionsSection');
      
      if (timeRestrictionsButton) {
        timeRestrictionsButton.classList.remove('selected');
      }
      
      if (timeRestrictionsButton && timeRestrictionsSection) {
        timeRestrictionsButton.addEventListener('click', function() {
          const isSelected = this.classList.contains('selected');
          
          if (isSelected) {
            this.classList.remove('selected');
            timeRestrictionsSection.classList.add('hidden');
            timeRestrictionsSection.style.display = 'none';

            const cycleBasedLimitCheckbox = doc.getElementById('wizardCycleBasedLimit');
            if (cycleBasedLimitCheckbox) {
              cycleBasedLimitCheckbox.checked = false;
            }
          } else {
            this.classList.add('selected');
            timeRestrictionsSection.classList.remove('hidden');
            timeRestrictionsSection.style.display = 'block';

            const dailyHoursOption = doc.querySelector('.restriction-option[data-type="daily_hours"]');
            const dailyHoursSection = doc.getElementById('wizardDailyHoursSection');
            if (dailyHoursOption && dailyHoursSection) {

              const allOptions = doc.querySelectorAll('.restriction-option');
              allOptions.forEach(opt => opt.classList.remove('active'));

              dailyHoursOption.classList.add('active');

              const allSections = doc.querySelectorAll('.restriction-type-section');
              allSections.forEach(section => {
                section.classList.add('hidden');
                section.style.display = 'none';
              });

              dailyHoursSection.classList.remove('hidden');
              dailyHoursSection.style.display = 'block';
            }
          }
        });
      }

      const restrictionOptions = doc.querySelectorAll('.restriction-option');
      restrictionOptions.forEach(option => {
        option.addEventListener('click', function() {

          restrictionOptions.forEach(opt => opt.classList.remove('active'));

          this.classList.add('active');

          const allSections = doc.querySelectorAll('.restriction-type-section');
          allSections.forEach(section => {
            section.classList.add('hidden');
            section.style.display = 'none';
          });

          const restrictionType = this.dataset.type;
          let targetSection = null;
          
          switch(restrictionType) {
            case 'daily_hours':
              targetSection = doc.getElementById('wizardDailyHoursSection');
              break;
            case 'weekly_days':
              targetSection = doc.getElementById('wizardWeeklyDaysSection');
              break;
            case 'specific_dates':
              targetSection = doc.getElementById('wizardSpecificDatesSection');
              break;
            case 'recurring':
              targetSection = doc.getElementById('wizardRecurringSection');
              break;
          }
          
          if (targetSection) {
            targetSection.classList.remove('hidden');
            targetSection.style.display = 'block';
          }
        });
      });

      const addDateBtn = doc.querySelector('.add-date');
      const dateInputContainer = doc.querySelector('.date-input-container');
      
      if (addDateBtn && dateInputContainer) {
        addDateBtn.addEventListener('click', function() {
          const dateInputRow = doc.createElement('div');
          dateInputRow.className = 'date-input-row';
          dateInputRow.innerHTML = `
            <input type="date" class="input" placeholder="Select date">
            <button type="button" class="btn btn-secondary remove-date">Remove</button>
          `;
          dateInputContainer.appendChild(dateInputRow);

          const removeBtn = dateInputRow.querySelector('.remove-date');
          removeBtn.addEventListener('click', function() {
            dateInputRow.remove();
          });
        });
      }

      const removeDateBtns = doc.querySelectorAll('.remove-date');
      removeDateBtns.forEach(btn => {
        btn.addEventListener('click', function() {
          this.closest('.date-input-row').remove();
        });
      });
    }
  
    function populateWizardTemplates() {
      const templateGrid = doc.getElementById('templateGrid');
      const categoryTabs = doc.getElementById('categoryTabs');
      if (!templateGrid || !categoryTabs) return;
      
      
      templateGrid.innerHTML = '';
      categoryTabs.innerHTML = '';
      
  
      fetchPreFilledRewards().then(templates => {
        
        if (templates && templates.success && templates.data) {
  
          let categories = [];
          let templatesData = templates.data;
          
  
          if (templatesData.reward_categories) {
            categories = Object.keys(templatesData.reward_categories);
            templatesData = templatesData.reward_categories;
          } else {
  
            categories = Object.keys(templatesData).filter(cat => cat !== 'quick_templates');
          }
          
  
          if (templates.data.quick_templates) {
            categories.unshift('quick_templates');
          }
          
  
          
          categories.forEach((category, index) => {
            const tab = doc.createElement('button');
            tab.className = `category-tab ${index === 0 ? 'active' : ''}`;
            tab.textContent = category.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
            tab.dataset.category = category;
            tab.addEventListener('click', () => {
  
              categoryTabs.querySelectorAll('.category-tab').forEach(t => t.classList.remove('active'));
              tab.classList.add('active');
  
              if (category === 'quick_templates') {
                showTemplatesForCategory(category, templates.data.quick_templates);
              } else {
                showTemplatesForCategory(category, templatesData[category]);
              }
            });
            categoryTabs.appendChild(tab);
          });
          
  
          if (templates.data.quick_templates) {
            showTemplatesForCategory('quick_templates', templates.data.quick_templates);
          } else if (categories.length > 0) {
  
            showTemplatesForCategory(categories[0], templatesData[categories[0]]);
          }
        }
      }).catch(error => {
        console.error('Failed to load pre-filled templates:', error);
      });
      
  
      loadSavedTemplates();
      
    }
    

    function selectTemplate(templateKey) {
      selectedTemplate = { name: templateKey };
      
  
      doc.querySelectorAll('.template-card').forEach(card => {
        card.classList.remove('selected');
      });
      
      const selectedCard = doc.querySelector(`[data-template="${templateKey}"]`);
      if (selectedCard) {
        selectedCard.classList.add('selected');
      }
      
  
      applyTemplateRewards(templateKey);
    }
  
    function useSavedTemplate(templateName) {
      fetchSavedTemplates().then(templates => {
        if (templates && templates.success && templates.data) {
        const template = templates.data.find(t => t.name === templateName);
        if (template && Array.isArray(template.rewards)) {
          wizardRewards = template.rewards.map(reward => {
            if (reward.vehicle && reward.amount !== undefined) {
              return { vehicle: true, model: reward.model || reward.vehicle };
            }
            return reward;
          });
          updateWizardRewardsTable();
          updateRewardsSummary();
          toast('Template Applied', `${templateName} template applied successfully`, 'success');
          } else {
            toast('Error', 'Invalid template data structure', 'error');
          }
        } else {
          toast('Error', 'Template not found', 'error');
        }
      });
    }
  
    async function quickGenerateCode(category, templateName) {
      try {
        let rewards = [];
        
        if (category === 'saved') {
  
          const templates = await fetchSavedTemplates();
          if (templates && templates.success && templates.data) {
            const template = templates.data.find(t => t.name === templateName);
            if (template && Array.isArray(template.rewards)) {
              rewards = template.rewards;
            }
          }
        } else {
  
          const templates = await fetchPreFilledRewards();
          if (templates && templates.success && templates.data && templates.data[category] && templates.data[category][templateName]) {
            const templateRewards = templates.data[category][templateName];
            if (Array.isArray(templateRewards)) {
              rewards = templateRewards;
            }
          }
        }
        
        if (rewards.length === 0) {
          toast('Error', 'No rewards found in template', 'error');
          return;
        }
        
  
        const generateRandom = (length) => {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
          let result = '';
          for (let i = 0; i < length; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
          }
          return result;
        };
        
        const randomCode = generateRandom(8);
        
  
        await nui('createCode', {
          rewards: rewards,
          code: randomCode,
          uses: 1,
          perUserLimit: 1,
          expiry: null
        });
        
        toast('Code Generated', `Quick code ${randomCode} generated successfully`, 'success');
        
  
        refreshAll();
        
      } catch (error) {
        console.error('Quick generate error:', error);
        toast('Error', 'Failed to generate code', 'error');
      }
    }
  
    function applyTemplateRewards(templateKey) {
      fetchPreFilledRewards().then(templates => {
        if (templates && templates.success && templates.data && templates.data.quick_templates && templates.data.quick_templates[templateKey]) {
          const template = templates.data.quick_templates[templateKey];
      const templateRewards = template.rewards || [];
      
      if (Array.isArray(templateRewards)) {
        wizardRewards = templateRewards.map(reward => {
          if (reward.vehicle && reward.amount !== undefined) {
            const normalized = { vehicle: true, model: reward.model || reward.vehicle };
            if (reward.label) normalized.label = reward.label;
            return normalized;
          }
          return reward;
        });
            updateWizardRewardsTable();
            updateWizardSummary();
            toast('Template Applied', `${template.name} template applied successfully`, 'success');
          } else {
            toast('Error', 'Invalid template data structure', 'error');
          }
        } else {
          toast('Error', 'Template not found', 'error');
        }
      });
    }
  
    function populateRewardCategories() {
      const categorySelect = doc.getElementById('rewardCategorySelect');
      if (!categorySelect) return;
      
      fetchPreFilledRewards().then(templates => {
        if (templates && templates.success && templates.data) {
          categorySelect.innerHTML = '<option value="">Select Category</option>';
          Object.keys(templates.data).forEach(category => {
            const option = doc.createElement('option');
            option.value = category;
            option.textContent = category;
            categorySelect.appendChild(option);
          });
        }
      });
    }
  
    function populateCategoryRewards() {
      const category = doc.getElementById('rewardCategorySelect')?.value;
      const rewardOptions = doc.getElementById('rewardOptions');
      if (!category || !rewardOptions) return;
      
      fetchPreFilledRewards().then(templates => {
        if (templates && templates.success && templates.data && templates.data[category]) {
          rewardOptions.innerHTML = '';
          Object.entries(templates.data[category]).forEach(([name, rewards]) => {
            const option = doc.createElement('div');
            option.className = 'reward-option';
            
            let previewText = 'No rewards';
            if (Array.isArray(rewards) && rewards.length > 0) {
              const previewRewards = rewards.slice(0, 2).map(reward => {
                if (reward.item) return `<i class='fas fa-box'></i> ${reward.amount || 1}x ${reward.item}`;
                if (reward.money) return `<i class='fas fa-dollar-sign'></i> $${reward.amount || 0}`;
                if (reward.vehicle) return `<i class='fas fa-car'></i> ${reward.model || reward.vehicle}`;
                return 'Unknown reward';
              }).join('<br>');
              previewText = previewRewards;
              if (rewards.length > 2) {
                previewText += `<br>+${rewards.length - 2} more...`;
              }
            }
            
            option.innerHTML = `
              <div class="reward-option-name">${name}</div>
              <div class="reward-option-preview">
                ${previewText}
              </div>
            `;
            option.addEventListener('click', () => {
              if (Array.isArray(rewards)) {
              wizardRewards = rewards.map(reward => {
                if (reward.vehicle && reward.amount !== undefined) {
                  const normalized = { vehicle: true, model: reward.model || reward.vehicle };
                  if (reward.label) normalized.label = reward.label;
                  return normalized;
                }
                return reward;
              });
              updateWizardRewardsTable();
              updateRewardsSummary();
              toast('Rewards Applied', `${name} rewards applied successfully`, 'success');
              } else {
                toast('Error', 'Invalid rewards data', 'error');
              }
            });
            rewardOptions.appendChild(option);
          });
        }
      });
    }
  
    function addWizardReward() {
      const rewardType = doc.getElementById('wizardRewardType')?.value;
      const rewardName = doc.getElementById('wizardRewardName')?.value?.trim();
      const rewardLabel = doc.getElementById('wizardRewardLabel')?.value?.trim();
      const rewardAmount = parseInt(doc.getElementById('wizardRewardAmount')?.value || '1');

      if (!rewardName && rewardType !== 'money') {
        toast('Validation Error', 'Please enter a reward name', 'error');
        return false;
      }
      
      let reward;
      if (rewardType === 'item') {
        reward = { item: rewardName, amount: rewardAmount };
        if (rewardLabel) reward.label = rewardLabel;
      } else if (rewardType === 'money') {
        reward = { money: true, amount: rewardAmount };
      } else if (rewardType === 'vehicle') {
        reward = { vehicle: true, model: rewardName };
        if (rewardLabel) reward.label = rewardLabel;
      }
      
      if (reward) {
        wizardRewards.push(reward);
        updateWizardRewardsTable();
        updateRewardsSummary();
        
        doc.getElementById('wizardRewardName').value = '';
        const labelInput = doc.getElementById('wizardRewardLabel');
        if (labelInput) labelInput.value = '';
        doc.getElementById('wizardRewardAmount').value = '1';
        
        toast('Reward Added', 'Reward added successfully', 'success');
      }
    }
  
    function updateWizardRewardsTable() {
      const tbody = doc.getElementById('wizardRewardsTbody');
      if (!tbody) return;
      
      tbody.innerHTML = '';
      wizardRewards.forEach((reward, index) => {
        const row = doc.createElement('tr');
        let type = 'Item', name = '', amount = reward.amount || 1;
        
        if (reward.money) {
          type = 'Money';
          name = 'Cash';
        } else if (reward.vehicle) {
          type = 'Vehicle';
          name = formatRewardDisplayName(reward.model || '', reward.label);
          amount = '-';
        } else {
          name = formatRewardDisplayName(reward.item || '', reward.label);
        }
        
        row.innerHTML = `
          <td>${escapeHtml(type)}</td>
          <td>${escapeHtml(name)}</td>
          <td>${escapeHtml(String(amount))}</td>
          <td><button class="remove-btn" onclick="removeWizardReward(${index})">Remove</button></td>
        `;
        tbody.appendChild(row);
      });
    }
  
    function removeWizardReward(index) {
      wizardRewards.splice(index, 1);
      updateWizardRewardsTable();
      updateRewardsSummary();
    }
  
    function clearWizardRewards() {
      wizardRewards = [];
      updateWizardRewardsTable();
      updateRewardsSummary();
    }
  
    function updateRewardsSummary() {
      let totalItems = 0;
      let totalMoney = 0;
      let totalVehicles = 0;
      
      wizardRewards.forEach(reward => {
        if (reward.item) totalItems += reward.amount || 1;
        if (reward.money) totalMoney += reward.amount || 0;
        if (reward.vehicle) totalVehicles += 1;
      });
      
      doc.getElementById('totalItems').textContent = totalItems;
      doc.getElementById('totalMoney').textContent = totalMoney;
      doc.getElementById('totalVehicles').textContent = totalVehicles;
    }
  
    function updateWizardSummary() {
      const code = doc.getElementById('wizardCustomCode')?.value || '';
      const uses = doc.getElementById('wizardUses')?.value || '0';
      const perUser = doc.getElementById('wizardPerUser')?.value || '0';
      
      doc.getElementById('summaryCode').textContent = code;
      doc.getElementById('summaryUses').textContent = uses === '0' ? 'Unlimited' : uses;
      doc.getElementById('summaryPerUser').textContent = perUser === '0' ? 'Unlimited' : perUser;
      
  
      const activeExpiryBtn = doc.querySelector('.expiry-btn.active');
      const expiryMethod = activeExpiryBtn?.dataset.expiry || 'never';
      if (expiryMethod === 'relative') {
        const hours = doc.getElementById('relativeHours')?.value || '0';
        doc.getElementById('summaryExpiry').textContent = `${hours} hours`;
      } else if (expiryMethod === 'specific') {
        const date = doc.getElementById('specificExpiry')?.value || '';
        doc.getElementById('summaryExpiry').textContent = date;
      } else {
        doc.getElementById('summaryExpiry').textContent = 'Never expires';
      }
      
  
      let rewardsText = 'No rewards';
      if (wizardRewards && wizardRewards.length > 0) {
        const rewardDescriptions = wizardRewards.map(reward => {
          if (reward.item) return `${reward.amount}x ${reward.item}`;
          if (reward.money) return `$${reward.amount}`;
          if (reward.vehicle) return `Vehicle: ${reward.model}`;
          return 'Unknown reward';
        });
        rewardsText = rewardDescriptions.join(', ');
      }
      doc.getElementById('summaryRewards').textContent = rewardsText;

      const timeRestrictionsEnabled = doc.getElementById('wizardTimeRestrictionsEnabled')?.classList.contains('selected') || false;
      const summaryTimeRestrictionsDiv = doc.getElementById('summaryTimeRestrictions');
      const summaryTimeRestrictionsValue = doc.getElementById('summaryTimeRestrictionsValue');
      
      if (timeRestrictionsEnabled) {
        const activeRestrictionOption = doc.querySelector('.restriction-option.active');
        const restrictionType = activeRestrictionOption?.dataset.type || 'daily_hours';
        let timeRestrictionsText = '';
        
        switch(restrictionType) {
          case 'daily_hours':
            const startHour = doc.getElementById('wizardStartHour')?.value || '09:00';
            const endHour = doc.getElementById('wizardEndHour')?.value || '17:00';
            timeRestrictionsText = `Daily: ${startHour} - ${endHour}`;
            break;
          case 'weekly_days':
            const selectedDays = [];
            const dayCheckboxes = doc.querySelectorAll('#wizardWeeklyDaysSection input[type="checkbox"]:checked');
            dayCheckboxes.forEach(checkbox => {
              const dayName = checkbox.nextElementSibling.textContent;
              selectedDays.push(dayName);
            });
            timeRestrictionsText = selectedDays.length > 0 ? `Weekly: ${selectedDays.join(', ')}` : 'Weekly: No days selected';
            break;
          case 'specific_dates':
            const dateInputs = doc.querySelectorAll('#wizardSpecificDatesSection input[type="date"]');
            const selectedDates = [];
            dateInputs.forEach(input => {
              if (input.value) selectedDates.push(input.value);
            });
            timeRestrictionsText = selectedDates.length > 0 ? `Specific dates: ${selectedDates.join(', ')}` : 'Specific dates: No dates selected';
            break;
          case 'recurring':
            const recurringType = doc.getElementById('wizardRecurringType')?.value || 'daily';
            const recurringPattern = doc.getElementById('wizardRecurringPattern')?.value || '';
            timeRestrictionsText = `Recurring: ${recurringType}${recurringPattern ? ` (${recurringPattern})` : ''}`;
            break;
          default:
            timeRestrictionsText = 'Unknown restriction type';
        }

        const customMessage = doc.getElementById('wizardTimeRestrictionsMessage')?.value?.trim();
        if (customMessage) {
          timeRestrictionsText += ` (Message: "${customMessage}")`;
        }
        
        summaryTimeRestrictionsValue.textContent = timeRestrictionsText;
      } else {
        summaryTimeRestrictionsValue.textContent = 'Disabled';
      }

      summaryTimeRestrictionsDiv.style.display = 'block';

      const cycleResetEnabled = doc.getElementById('wizardCycleBasedLimit')?.checked || false;
      const summaryCycleLimitDiv = doc.getElementById('summaryCycleLimit');
      const summaryCycleLimitValue = doc.getElementById('summaryCycleLimitValue');
      
      summaryCycleLimitValue.textContent = cycleResetEnabled ? 'Enabled' : 'Disabled';
      summaryCycleLimitDiv.style.display = 'block';

      const restrictEnabled = doc.getElementById('wizardRestrictToPlayerEnabled')?.checked === true;
      const summaryPlayerRestrictionValue = doc.getElementById('summaryPlayerRestrictionValue');
      if (summaryPlayerRestrictionValue) {
        if (restrictEnabled) {
          const identifierType = doc.getElementById('wizardPlayerIdentifierType')?.value || 'citizenid';
          const identifierValue = doc.getElementById('wizardPlayerIdentifierValue')?.value || '-';
          summaryPlayerRestrictionValue.textContent = `${identifierType}: ${identifierValue}`;
        } else {
          summaryPlayerRestrictionValue.textContent = 'Anyone';
        }
      }
      
      updateRewardsSummary();
    }
  
  
    async function copyCustomCode() {
      const customCode = doc.getElementById('wizardCustomCode')?.value?.trim();
      const copyBtn = doc.getElementById('copyCustomCode');
      
      if (!customCode) {
        toast('No Code', 'Please enter a code to copy', 'error');
        return;
      }
      
      let copied = false;
      
      try {
        const textArea = doc.createElement('textarea');
        textArea.value = customCode;
        textArea.style.position = 'fixed';
        textArea.style.top = '0';
        textArea.style.left = '0';
        textArea.style.width = '2em';
        textArea.style.height = '2em';
        textArea.style.padding = '0';
        textArea.style.border = 'none';
        textArea.style.outline = 'none';
        textArea.style.boxShadow = 'none';
        textArea.style.background = 'transparent';
        textArea.setAttribute('readonly', '');
        doc.body.appendChild(textArea);
        
        textArea.focus();
        textArea.select();
        textArea.setSelectionRange(0, customCode.length);
        
        const successful = doc.execCommand('copy');
        doc.body.removeChild(textArea);
        
        if (successful) {
          copied = true;
        }
      } catch (err) {
      }
      
      if (!copied) {
        const wizardCustomCodeField = doc.getElementById('wizardCustomCode');
        if (wizardCustomCodeField) {
          wizardCustomCodeField.focus();
          wizardCustomCodeField.select();
          wizardCustomCodeField.setSelectionRange(0, customCode.length);
        }
      }
      
      if (copied) {
        toast('Code Copied', 'Code copied to clipboard', 'success');
        
        if (copyBtn) {
          const originalHTML = copyBtn.innerHTML;
          copyBtn.classList.add('applied');
          copyBtn.innerHTML = '<i class="fas fa-check"></i> <span data-locale="UI_CODE_APPLIED">Applied</span>';
        
          const appliedText = typeof t === 'function' ? t('UI_CODE_APPLIED') : 'Applied';
          if (appliedText && appliedText !== 'UI_CODE_APPLIED') {
            const span = copyBtn.querySelector('span');
            if (span) span.textContent = appliedText;
          }
          
          setTimeout(() => {
            copyBtn.classList.remove('applied');
            copyBtn.innerHTML = originalHTML;
            
            const copyText = typeof t === 'function' ? t('UI_COPY_CODE') : 'Copy Code';
            if (copyText && copyText !== 'UI_COPY_CODE') {
              const span = copyBtn.querySelector('span');
              if (span) span.textContent = copyText;
            }
          }, 2000);
        }
      } else {
        toast('Code Selected', 'Code selected - press Ctrl+C to copy', 'success');
      }
    }
  
    async function copySummaryCode() {
      const summaryCodeElement = doc.getElementById('summaryCode');
      const summaryCode = summaryCodeElement?.textContent?.trim();
      const copyBtn = doc.getElementById('copySummaryCode');
      
      if (!summaryCode || summaryCode === '-') {
        toast('No Code', 'No code available to copy', 'error');
        return;
      }
      
      let copied = false;
      
      try {
        const textArea = doc.createElement('textarea');
        textArea.value = summaryCode;
        textArea.style.position = 'fixed';
        textArea.style.top = '0';
        textArea.style.left = '0';
        textArea.style.width = '2em';
        textArea.style.height = '2em';
        textArea.style.padding = '0';
        textArea.style.border = 'none';
        textArea.style.outline = 'none';
        textArea.style.boxShadow = 'none';
        textArea.style.background = 'transparent';
        textArea.setAttribute('readonly', '');
        doc.body.appendChild(textArea);
        
        textArea.focus();
        textArea.select();
        textArea.setSelectionRange(0, summaryCode.length);
        
        const successful = doc.execCommand('copy');
        doc.body.removeChild(textArea);
        
        if (successful) {
          copied = true;
        }
      } catch (err) {
      }
      
      if (!copied && summaryCodeElement) {
        const range = doc.createRange();
        range.selectNodeContents(summaryCodeElement);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
      }
      
      if (copied) {
        toast('Code Copied', 'Code copied to clipboard', 'success');
        
        if (copyBtn) {
          const originalHTML = copyBtn.innerHTML;
          copyBtn.classList.add('applied');
          copyBtn.innerHTML = '<i class="fas fa-check"></i> <span data-locale="UI_CODE_APPLIED">Applied</span>';
          
          const appliedText = typeof t === 'function' ? t('UI_CODE_APPLIED') : 'Applied';
          if (appliedText && appliedText !== 'UI_CODE_APPLIED') {
            const span = copyBtn.querySelector('span');
            if (span) span.textContent = appliedText;
          }
          
          setTimeout(() => {
            copyBtn.classList.remove('applied');
            copyBtn.innerHTML = originalHTML;
            
            const copyText = typeof t === 'function' ? t('UI_COPY_CODE') : 'Copy Code';
            if (copyText && copyText !== 'UI_COPY_CODE') {
              const span = copyBtn.querySelector('span');
              if (span) span.textContent = copyText;
            }
          }, 2000);
        }
      } else {
        toast('Code Selected', 'Code selected - press Ctrl+C to copy', 'success');
      }
    }
  
    async function saveWizardTemplate() {
      const templateName = doc.getElementById('templateName')?.value?.trim();
      if (!templateName) {
        toast('Validation Error', 'Please enter a template name', 'error');
        return;
      }
      
      if (wizardRewards.length === 0) {
        toast('Validation Error', 'Please add at least one reward', 'error');
        return;
      }
      
      try {
  
        await nui('saveTemplate', {
          name: templateName,
          rewards: wizardRewards
        });
      
      clearTemplateCaches();
      toast('Template Saved', 'Template saved successfully', 'success');
        
  
        doc.getElementById('templateName').value = '';
        
  
        populateWizardTemplates();
      } catch (error) {
        console.error('Failed to save template:', error);
        toast('Error', 'Failed to save template', 'error');
      }
    }
  
    function getExpirySettings() {
      const activeExpiryBtn = doc.querySelector('.expiry-btn.active');
      const expiryMethod = activeExpiryBtn?.getAttribute('data-expiry');
  
      
      if (expiryMethod === 'relative') {
        const hours = parseInt(doc.getElementById('relativeHours')?.value || '0');
        
        return { type: 'relative', hours };
      } else if (expiryMethod === 'specific') {
        const date = doc.getElementById('specificExpiry')?.value;
        
        return { type: 'specific', date };
      } else {
        return { type: 'never' };
      }
    }
  
    async function generateWizardCode() {
      const code = doc.getElementById('wizardCustomCode')?.value?.trim();
      const uses = parseInt(doc.getElementById('wizardUses')?.value || '0');
      const perUser = parseInt(doc.getElementById('wizardPerUser')?.value || '0');
      const expirySettings = getExpirySettings();
      
      if (!code) {
        toast('Validation Error', 'Please enter a code', 'error');
        return;
      }
      
      if (isNaN(uses) || uses < 0) {
        toast('Validation Error', 'Please select a valid uses value', 'error');
        return;
      }
      
      if (isNaN(perUser) || perUser < 0) {
        toast('Validation Error', 'Please select a valid per-user limit', 'error');
        return;
      }
      
      if (wizardRewards.length === 0) {
        toast('Validation Error', 'Please add at least one reward', 'error');
        return;
      }

      const restrictEnabled = doc.getElementById('wizardRestrictToPlayerEnabled')?.checked === true;
      const playerRestriction = {
        enabled: restrictEnabled,
        type: doc.getElementById('wizardPlayerIdentifierType')?.value || null,
        value: doc.getElementById('wizardPlayerIdentifierValue')?.value?.trim() || null
      };
      if (restrictEnabled && (!playerRestriction.type || !playerRestriction.value)) {
        toast('Validation Error', 'Player restriction requires identifier type and value', 'error');
        return;
      }
      
  
      let expiry = null;
      if (expirySettings.type === 'relative') {
        const expiryDate = new Date();
        expiryDate.setHours(expiryDate.getHours() + expirySettings.hours);
        expiry = expiryDate.toISOString().slice(0, 19).replace('T', ' ');
  
      } else if (expirySettings.type === 'specific') {
        expiry = expirySettings.date.replace('T', ' ') + ':00';
      } else {
      }

      const timeRestrictionsEnabled = doc.getElementById('wizardTimeRestrictionsEnabled')?.classList.contains('selected') || false;
      let timeRestrictions = null;
      
      if (timeRestrictionsEnabled) {
        const activeRestrictionOption = doc.querySelector('.restriction-option.active');
        const restrictionType = activeRestrictionOption?.dataset.type || 'daily_hours';
        const customMessage = doc.getElementById('wizardTimeRestrictionsMessage')?.value?.trim() || '';
        const cycleBasedLimit = doc.getElementById('wizardCycleBasedLimit')?.checked || false;
        
        timeRestrictions = {
          enabled: true,
          type: restrictionType,
          message: customMessage,
          cycle_based_limit: cycleBasedLimit,
          restrictions: {}
        };

        switch(restrictionType) {
          case 'daily_hours':
            const startHour = doc.getElementById('wizardStartHour')?.value || '09:00';
            const endHour = doc.getElementById('wizardEndHour')?.value || '17:00';
            timeRestrictions.restrictions.start_hour = parseInt(startHour.split(':')[0]);
            timeRestrictions.restrictions.end_hour = parseInt(endHour.split(':')[0]);
            break;
          case 'weekly_days':
            const selectedDays = [];
            const dayCheckboxes = doc.querySelectorAll('#wizardWeeklyDaysSection input[type="checkbox"]:checked');
            dayCheckboxes.forEach(checkbox => {

              const htmlDay = parseInt(checkbox.value);
              const luaDay = htmlDay === 7 ? 1 : htmlDay + 1;
              selectedDays.push(luaDay);
            });
            timeRestrictions.restrictions.allowed_days = selectedDays;
            break;
          case 'specific_dates':
            const selectedDates = [];
            const dateInputs = doc.querySelectorAll('#wizardSpecificDatesSection input[type="date"]');
            dateInputs.forEach(input => {
              if (input.value) selectedDates.push(input.value);
            });
            timeRestrictions.restrictions.allowed_dates = selectedDates;
            break;
          case 'recurring':
            const recurringType = doc.getElementById('wizardRecurringType')?.value || 'daily';
            const recurringPattern = doc.getElementById('wizardRecurringPattern')?.value || '';
            timeRestrictions.restrictions.recurring_type = recurringType;
            timeRestrictions.restrictions.recurring_pattern = recurringPattern;
            break;
        }
        
      }
      
      try {
        const createData = {
          customCode: code,
          uses: uses,
          perUserLimit: perUser,
          expiry: expiry,
          itemsJson: JSON.stringify(wizardRewards),
          timeRestrictions: timeRestrictions,
          playerRestriction: playerRestriction
        };

        toast('Create Code', 'Request sent.', 'success');
        await nui('adminCreate', createData);
        
        toast('Code Generated', 'Code generated successfully', 'success');
        hideWizardModal();
        refreshAll();
      } catch (error) {
        console.error('Code creation error:', error);
        toast('Creation Error', 'An error occurred while creating the code', 'error');
      }
    }
  
    function generateCodeFromWizard() {
      generateWizardCode();
    }
  
    function initializeWizard() {
    }
  
  
  
    function hideLoadingStates() {
      const loadingOverlays = doc.querySelectorAll('.global-loading-overlay, .loading-state, .loading-overlay');
      loadingOverlays.forEach(overlay => {
        overlay.classList.add('hidden');
        overlay.style.display = 'none';
      });
      
      const dashboardRoute = doc.getElementById('route-admin-dashboard');
      if (dashboardRoute) {
        dashboardRoute.classList.add('route-active');
        dashboardRoute.style.display = 'block';
      }
    }
  
  
    function setText(id, v) { 
      const el = doc.getElementById(id); 
      if (el) el.textContent = String(v); 
    }
  
    function setVal(id, v) { 
      const el = doc.getElementById(id); 
      if (el) el.value = v; 
    }
  
  
    function openBulkGenerateModal() {
      const modal = doc.getElementById('bulkGenerateModal');
      if (modal) {
        resetBulkGenerateModal();
        modal.classList.remove('hidden');
      }
    }

    function resetBulkGenerateModal() {
      if (typeof window.currentStep !== 'undefined') {
        window.currentStep = 1;
      }
      if (typeof window.updateStepDisplay === 'function') {
        window.updateStepDisplay();
      }
      
      const bulkAmount = doc.getElementById('bulkAmount');
      const bulkPattern = doc.getElementById('bulkPattern');
      const bulkUses = doc.getElementById('bulkUses');
      const bulkPerUser = doc.getElementById('bulkPerUser');
      const bulkExpiry = doc.getElementById('bulkExpiry');
      
      if (bulkAmount) bulkAmount.value = '100';
      if (bulkPattern) bulkPattern.value = 'CODE-{RANDOM:6}';
      if (bulkUses) bulkUses.value = '1';
      if (bulkPerUser) bulkPerUser.value = '1';
      if (bulkExpiry) bulkExpiry.value = '';
      
      const timeRestrictionsEnabled = doc.getElementById('bulkTimeRestrictionsEnabled');
      const timeRestrictionsRow = doc.getElementById('timeRestrictionsRow');
      const bulkStartTime = doc.getElementById('bulkStartTime');
      const bulkEndTime = doc.getElementById('bulkEndTime');
      
      if (timeRestrictionsEnabled) timeRestrictionsEnabled.checked = false;
      if (timeRestrictionsRow) timeRestrictionsRow.style.display = 'none';
      if (bulkStartTime) bulkStartTime.value = '09:00';
      if (bulkEndTime) bulkEndTime.value = '17:00';
      
      const dayCheckboxes = {
        'bulkDayMon': true,
        'bulkDayTue': true,
        'bulkDayWed': true,
        'bulkDayThu': true,
        'bulkDayFri': true,
        'bulkDaySat': false,
        'bulkDaySun': false
      };
      
      Object.keys(dayCheckboxes).forEach(id => {
        const checkbox = doc.getElementById(id);
        if (checkbox) checkbox.checked = dayCheckboxes[id];
      });
      
      const rewardsList = doc.getElementById('bulkRewardsList');
      if (rewardsList) {
        rewardsList.innerHTML = `
          <div class="reward-item">
            <select class="reward-type" onchange="toggleRewardFields(this); updatePreview()">
              <option value="item" data-locale="UI_WIZARD_REWARD_ITEM">Item</option>
              <option value="money" data-locale="UI_WIZARD_REWARD_MONEY">Money</option>
              <option value="vehicle" data-locale="UI_WIZARD_REWARD_VEHICLE">Vehicle</option>
            </select>
            <input type="text" class="reward-name" placeholder="Item name / Vehicle model" onchange="updatePreview()" data-locale-placeholder="UI_WIZARD_REWARD_NAME_PLACEHOLDER">
            <input type="text" class="reward-amount" value="" placeholder="Amount" onchange="updatePreview()" data-locale-placeholder="UI_WIZARD_REWARD_AMOUNT_PLACEHOLDER">
            <button type="button" class="btn btn-sm remove-reward" onclick="removeRewardItem(this); updatePreview()" data-locale="UI_REMOVE">Remove</button>
          </div>
        `;
        const selectElement = rewardsList.querySelector('.reward-type');
        if (selectElement && typeof window.toggleRewardFields === 'function') {
          window.toggleRewardFields(selectElement);
        }
      }
      
      requestAnimationFrame(() => {
        if (typeof window.updatePreview === 'function') {
          window.updatePreview();
        }
      });
    }
    
    function hideBulkGenerateModal() {
      const modal = doc.getElementById('bulkGenerateModal');
      if (modal) {
        modal.classList.add('hidden');
        resetBulkGenerateModal();
      }
    }
  
    async function generateBulkCodes() {
      const amount = parseInt(doc.getElementById('bulkAmount')?.value || '100');
      const pattern = doc.getElementById('bulkPattern')?.value || 'CODE-{RANDOM:6}';
      const uses = parseInt(doc.getElementById('bulkUses')?.value || '1');
      const perUser = parseInt(doc.getElementById('bulkPerUser')?.value || '1');
      const expiry = parseInt(doc.getElementById('bulkExpiry')?.value || '24');
      
      const rewardItems = doc.querySelectorAll('#bulkRewardsList .reward-item');
      const rewards = [];
      
      rewardItems.forEach((item) => {
        const typeSelect = item.querySelector('.reward-type');
        if (!typeSelect) return;
        
        const nameInput = item.querySelector('.reward-name');
        const amountInput = item.querySelector('.reward-amount');
        
        const type = typeSelect.value;
        const name = (nameInput && nameInput.style.display !== 'none') ? nameInput.value.trim() : '';
        
        if (type === 'money') {
          const moneyAmount = parseFloat(name);
          if (!isNaN(moneyAmount) && moneyAmount > 0) {
            rewards.push({ money: true, amount: moneyAmount, option: 'cash' });
          }
        } else if (type === 'item' && name) {
          const amount = (amountInput && amountInput.style.display !== 'none') ? parseFloat(amountInput.value) || 1 : 1;
          const reward = { item: name, amount: amount };
          const labelInput = item.querySelector('.reward-label');
          const label = labelInput && labelInput.style.display !== 'none' ? labelInput.value.trim() : '';
          if (label) reward.label = label;
          rewards.push(reward);
        } else if (type === 'vehicle' && name) {
          rewards.push({ vehicle: true, model: name });
        }
      });
      
      if (rewards.length === 0) {
        toast('Validation Error', 'Please add at least one valid reward before generating codes.', 'error');
        return;
      }
      
      try {
        await nui('bulkGenerateCodes', {
          amount: amount,
          pattern: pattern,
          uses: uses,
          perUserLimit: perUser,
          expiryHours: expiry,
          rewards: rewards
        });
        hideBulkGenerateModal();
        refreshAll();
      } catch (error) {
        console.error('Bulk generation error:', error);
        toast('Generation Error', 'An error occurred while generating codes', 'error');
        hideBulkGenerateModal();
      }
    }
  
    async function loadAllCodes() {
      const codeList = doc.getElementById('codeList');
      const loadingState = doc.getElementById('codeListLoading');
      
      if (window.allCodes && Array.isArray(window.allCodes) && window.allCodes.length > 0) {
        displayAllCodes(window.allCodes);
        if (loadingState) {
          loadingState.style.display = 'none';
        }
      } else {
        if (codeList) {
          codeList.innerHTML = '<div class="empty-state">Loading codes...</div>';
        }
        if (loadingState) {
          loadingState.style.display = 'none';
        }
      }
      
      try {
        const codes = await nuiRet('getAllCodesForSearch', {});
        if (codes && Array.isArray(codes)) {
          window.allCodes = codes;
          displayAllCodes(codes);
        }
      } catch (error) {
        console.error('Failed to load codes:', error);
        if (!window.allCodes || !Array.isArray(window.allCodes) || window.allCodes.length === 0) {
          window.allCodes = [];
          if (codeList) {
            codeList.innerHTML = '<div class="empty-state">Failed to load codes. Please try refreshing.</div>';
          }
        }
        if (loadingState) {
          loadingState.style.display = 'none';
        }
      }
    }
  
    function updateAllCodesData(codes) {
      if (codes && Array.isArray(codes)) {
        window.allCodes = codes;
        displayAllCodes(codes);
      } else {
        console.error('Invalid codes response:', codes);
        window.allCodes = [];
  
        const codeList = doc.getElementById('codeList');
        if (codeList) {
          codeList.innerHTML = '<div class="empty-state">No codes found</div>';
        }
      }
    }
  
    function updateWeeklyStats(stats) {
      if (!stats) return;
      const safe = {
        generated: stats.generated || { current: 0, previous: 0, change: 0 },
        active: stats.active || { current: 0, previous: 0, change: 0 },
        redeemed: stats.redeemed || { current: 0, previous: 0, change: 0 },
        expired: stats.expired || { current: 0, previous: 0, change: 0 },
        lastWeek: stats.lastWeek || { current: 0, change: 0 },
        thisWeek: stats.thisWeek || { current: 0, change: 0 }
      };

      const generatedValue = doc.getElementById('weeklyCodesGenerated');
      if (generatedValue) generatedValue.textContent = safe.generated.current;

      const activeValue = doc.getElementById('weeklyActiveCodes');
      const activeLastWeek = doc.getElementById('weeklyActiveLastWeek');
      const activeChange = doc.getElementById('weeklyActiveChange');
      if (activeValue) activeValue.textContent = safe.active.current;
      if (activeLastWeek) {
        activeLastWeek.textContent = safe.active.previous !== undefined ? safe.active.previous : '-';
      }
      if (activeChange) {
        updateStatChange(activeChange, safe.active.change);
      }

      const redeemedValue = doc.getElementById('weeklyRedeemedCodes');
      const redeemedLastWeek = doc.getElementById('weeklyRedeemedLastWeek');
      const redeemedChange = doc.getElementById('weeklyRedeemedChange');
      if (redeemedValue) redeemedValue.textContent = safe.redeemed.current;
      if (redeemedLastWeek) {
        redeemedLastWeek.textContent = safe.redeemed.previous !== undefined ? safe.redeemed.previous : '-';
      }
      if (redeemedChange) {
        updateStatChange(redeemedChange, safe.redeemed.change);
      }

      const expiredValue = doc.getElementById('weeklyExpiredCodes');
      const expiredLastWeek = doc.getElementById('weeklyExpiredLastWeek');
      const expiredChange = doc.getElementById('weeklyExpiredChange');
      if (expiredValue) expiredValue.textContent = safe.expired.current;
      if (expiredLastWeek) {
        expiredLastWeek.textContent = safe.expired.previous !== undefined ? safe.expired.previous : '-';
      }
      if (expiredChange) {
        updateStatChange(expiredChange, safe.expired.change);
      }

      const lastWeekValue = doc.getElementById('weeklyLastWeekTickets');
      const lastWeekChange = doc.getElementById('weeklyLastWeekChange');
      if (lastWeekValue) lastWeekValue.textContent = safe.lastWeek.current || 0;
      if (lastWeekChange) {
        updateStatChange(lastWeekChange, safe.lastWeek.change || 0);
      }

      const thisWeekValue = doc.getElementById('weeklyThisWeekTickets');
      const thisWeekChange = doc.getElementById('weeklyThisWeekChange');
      if (thisWeekValue) thisWeekValue.textContent = safe.thisWeek.current || 0;
      if (thisWeekChange) {
        updateStatChange(thisWeekChange, safe.thisWeek.change || 0);
      }
    }
  
    function updateStatChange(element, change) {
      if (!element) return;
      
      const changeText = element.querySelector('.change-text');
      const changeIcon = element.querySelector('.change-icon');
      
      if (!changeText || !changeIcon) return;

      element.classList.remove('positive', 'negative', 'neutral');
      
      if (change > 0) {
        element.classList.add('positive');
        changeText.textContent = `+${change}%`;
      } else if (change < 0) {
        element.classList.add('negative');
        changeText.textContent = `${change}%`;
      } else {
        element.classList.add('neutral');
        changeText.textContent = '0%';
      }
    }
  
    function updateDailyStats(stats) {
      if (!stats) return;
  
      const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
      
      days.forEach(day => {
        const dayData = stats[day];
        if (!dayData) return;

        const countElement = doc.getElementById(`${day}Count`);
        if (countElement) {
          countElement.textContent = dayData.current;
        }

        const changeElement = doc.getElementById(`${day}Change`);
        if (changeElement) {
          updateStatChange(changeElement, dayData.change);
        }

        const previousElement = doc.getElementById(`${day}Previous`);
        if (previousElement) {
          previousElement.textContent = `Last: ${dayData.previous}`;
        }
      });
    }
  
    function updateRewardsStats(stats) {
      if (!stats) return;

      const moneyContainer = doc.getElementById('topMoneyRewards');
      if (moneyContainer) {
        if (stats.topMoney && stats.topMoney.length > 0) {
          moneyContainer.innerHTML = stats.topMoney.slice(0, 3).map(reward => `
            <div class="reward-item">
              <div class="reward-name">$${escapeHtml((reward.amount || 0).toLocaleString())} (${escapeHtml(reward.name)})</div>
              <div class="reward-count">${escapeHtml(reward.count)}</div>
            </div>
          `).join('');
        } else {
          moneyContainer.innerHTML = '<div class="reward-item"><div class="reward-name">No money rewards yet</div><div class="reward-count">-</div></div>';
        }
      }

      const itemContainer = doc.getElementById('topItemRewards');
      if (itemContainer) {
        if (stats.topItems && stats.topItems.length > 0) {
          itemContainer.innerHTML = stats.topItems.slice(0, 3).map(reward => `
            <div class="reward-item">
              <div class="reward-name">${escapeHtml(reward.name)} (x${escapeHtml(reward.amount)})</div>
              <div class="reward-count">${escapeHtml(reward.count)}</div>
            </div>
          `).join('');
        } else {
          itemContainer.innerHTML = '<div class="reward-item"><div class="reward-name">No item rewards yet</div><div class="reward-count">-</div></div>';
        }
      }

      const vehicleContainer = doc.getElementById('topVehicleRewards');
      if (vehicleContainer) {
        if (stats.topVehicles && stats.topVehicles.length > 0) {
          vehicleContainer.innerHTML = stats.topVehicles.slice(0, 3).map(reward => `
            <div class="reward-item">
              <div class="reward-name">${escapeHtml(reward.name)}</div>
              <div class="reward-count">${escapeHtml(reward.count)}</div>
            </div>
          `).join('');
        } else {
          vehicleContainer.innerHTML = '<div class="reward-item"><div class="reward-name">No vehicle rewards yet</div><div class="reward-count">-</div></div>';
        }
      }
    }
  
    function displaySearchResults(codes) {
      
    }
  
    function filterCodes() {
      const codeSearch = doc.getElementById('codeSearch')?.value.toLowerCase() || '';
      const creatorSearch = doc.getElementById('creatorSearch')?.value.toLowerCase() || '';
      const dateFrom = doc.getElementById('dateFrom')?.value || '';
      const dateTo = doc.getElementById('dateTo')?.value || '';
      const statusFilter = doc.getElementById('statusFilter')?.value || '';
      const rewardTypeFilter = doc.getElementById('rewardTypeFilter')?.value || '';
      const sortOrder = doc.getElementById('sortOrder')?.value || 'newest';
      
      if (!window.allCodes) {
        
        return;
      }
      
      const filteredCodes = window.allCodes.filter(code => {
  
        if (codeSearch && !code.code.toLowerCase().includes(codeSearch)) {
          return false;
        }
        
  
        if (creatorSearch && !code.created_by.toLowerCase().includes(creatorSearch)) {
          return false;
        }
        
  
        if (dateFrom || dateTo) {
          const createdDate = new Date(code.created_at);
          if (dateFrom && createdDate < new Date(dateFrom)) {
            return false;
          }
          if (dateTo && createdDate > new Date(dateTo)) {
            return false;
          }
        }
        
  
        if (statusFilter) {
          let status = 'Active';
          
  
          if (code.expiry && code.expiry !== 'Never') {
            const expiryTime = new Date(code.expiry).getTime();
            if (!Number.isNaN(expiryTime) && expiryTime < Date.now()) {
              status = 'Expired';
            }
          }
          
  
          if (code.max_uses && code.max_uses > 0 && code.uses >= code.max_uses) {
            status = 'Redeemed';
          } else if (code.max_uses === 0 || (code.max_uses && code.uses >= code.max_uses)) {
  
            status = 'Redeemed';
          }
          
  
          let expectedStatus = statusFilter;
          if (statusFilter === 'active') expectedStatus = 'Active';
          else if (statusFilter === 'expired') expectedStatus = 'Expired';
          else if (statusFilter === 'redeemed') expectedStatus = 'Redeemed';
          
          if (status !== expectedStatus) {
            return false;
          }
        }
        
  
        if (rewardTypeFilter && code.items) {
          const hasRewardType = code.items.some(reward => {
            if (rewardTypeFilter === 'item' && reward.item) return true;
            if (rewardTypeFilter === 'money' && reward.money) return true;
            if (rewardTypeFilter === 'vehicle' && reward.vehicle) return true;
            return false;
          });
          
          if (!hasRewardType) {
            return false;
          }
        }
        
        return true;
      });

      const sortedCodes = filteredCodes.sort((a, b) => {
        switch (sortOrder) {
          case 'newest':
            return new Date(b.created_at) - new Date(a.created_at);
          case 'oldest':
            return new Date(a.created_at) - new Date(b.created_at);
          case 'alphabetical':
            return a.code.localeCompare(b.code);
          case 'uses':
            return (b.uses || 0) - (a.uses || 0);
          case 'expiry':

            if (!a.expiry || a.expiry === 'Never') return 1;
            if (!b.expiry || b.expiry === 'Never') return -1;
            return new Date(a.expiry) - new Date(b.expiry);
          default:
            return 0;
        }
      });
  
      const resultsCount = doc.getElementById('resultsCount');
      if (resultsCount) {
        resultsCount.textContent = `${sortedCodes.length} codes found`;
      }
      
  
      displayAllCodes(sortedCodes);
    }
  
    function displayAllCodes(codes) {
      const codeList = doc.getElementById('codeList');
      if (!codeList) {
        return;
      }
      
      const resultsCount = doc.getElementById('resultsCount');
      if (resultsCount) {
        resultsCount.textContent = `${codes.length} codes found`;
      }
      
      
      if (!codes || codes.length === 0) {
  
        if (window.allCodes && window.allCodes.length > 0) {
  
          codeList.innerHTML = '<div class="empty-state">No codes match your search criteria</div>';
        } else {
  
          codeList.innerHTML = '<div class="empty-state">No codes generated yet</div>';
        }
        return;
      }
      
      const htmlParts = [];
      codes.forEach(codeData => {
        const code = codeData.code || 'Unknown';
        const uses = codeData.uses || 0;
        const unlimited = codeData.unlimited || false;
        const createdBy = codeData.created_by || 'Unknown';
        const created = formatDateForDisplay(codeData.created_at) || 'N/A';
        const rawExp = codeData.expiry || "Never";
        const expiry = formatDateForDisplay(rawExp) || 'Never';
        
        let isExpired = false;
        if (rawExp && rawExp !== 'Never') {
          const expiryTime = new Date(rawExp).getTime();
          if (!Number.isNaN(expiryTime)) {
            isExpired = expiryTime < Date.now();
          }
        }
  
        let status = t('UI_ACTIVE');
        let statusClass = 'status-active';
        
        if (isExpired) {
          status = unlimited ? `${t('UI_EXPIRED')} (${t('UI_UNLIMITED')})` : t('UI_EXPIRED');
          statusClass = 'status-expired';
        } else if (unlimited) {
          status = `${t('UI_ACTIVE')} (${t('UI_UNLIMITED')})`;
          statusClass = 'status-unlimited';
        } else if (uses <= 0) {
          status = t('UI_DASHBOARD_REDEEMED');
          statusClass = 'status-redeemed';
        } else {
          status = t('UI_ACTIVE');
          statusClass = 'status-active';
        }
        
        const safeCode = escapeHtml(code);
        const safeCreatedBy = escapeHtml(createdBy);
        const safeCreated = escapeHtml(created);
        const safeExpiry = escapeHtml(expiry);
        const canEdit = window.userPermissions?.permissions?.canEdit || (window.userPermissions?.level >= 2);
        const canDelete = window.userPermissions?.permissions?.canDelete || (window.userPermissions?.level >= 2);

        htmlParts.push(`
          <div class="code-card" data-code="${safeCode}">
            <div class="code-header">
              <div class="code-name">${safeCode}</div>
              <div class="code-status ${statusClass}">${escapeHtml(status)}</div>
            </div>
            <div class="code-details">
              ${unlimited ? '' : `<div class="code-info">
                <span class="label">${t('UI_LABEL_USES')}</span> <span class="value">${escapeHtml(uses)}</span>
              </div>`}
              <div class="code-info">
                <span class="label">${t('UI_LABEL_CREATED_BY')}</span> <span class="value">${safeCreatedBy}</span>
              </div>
              <div class="code-info">
                <span class="label">${t('UI_LABEL_CREATED')}</span> <span class="value">${safeCreated}</span>
              </div>
              <div class="code-info">
                <span class="label">${t('UI_LABEL_EXPIRY')}</span> <span class="value">${safeExpiry}</span>
              </div>
            </div>
            <div class="code-actions">
              <button class="btn btn-xs code-view-btn" data-code="${safeCode}">${t('UI_BUTTON_VIEW')}</button>
              ${canEdit ? `<button class="btn btn-xs btn-secondary code-edit-btn" data-code="${safeCode}">${t('UI_BUTTON_EDIT')}</button>` : ''}
              ${canDelete ? `<button class="btn btn-xs btn-danger code-delete-btn" data-code="${safeCode}">${t('UI_BUTTON_DELETE')}</button>` : ''}
            </div>
          </div>
        `);
      });
      
      codeList.innerHTML = htmlParts.join('');
      
      codeList.querySelectorAll('.code-view-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const code = btn.closest('.code-card')?.dataset.code;
          if (code) viewCode(code);
        });
      });
      codeList.querySelectorAll('.code-edit-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const code = btn.closest('.code-card')?.dataset.code;
          if (code) editCode(code);
        });
      });
      codeList.querySelectorAll('.code-delete-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const code = btn.closest('.code-card')?.dataset.code;
          if (code) deleteCode(code);
        });
      });

      codeList.querySelectorAll('.code-card').forEach(card => {
        card.addEventListener('click', (e) => {
  
          if (e.target.tagName === 'BUTTON') return;
          
          const code = card.dataset.code;
          if (code) {
            showRoute('code-view');
            loadCodeDetails(code);
          }
        });
      });
    }
  
  
    async function viewCode(code) {
      try {
        showRoute('code-view');
        await loadCodeDetails(code);
      } catch (error) {
        console.error('Error viewing code:', error);
        toast('Error', 'Failed to load code details', 'error');
      }
    }
  
    async function editCode(code) {
      try {
        showRoute('code-edit');
        await openEditPage(code);
      } catch (error) {
        console.error('Error editing code:', error);
        toast('Error', 'Failed to load code for editing', 'error');
      }
    }
  
    async function deleteCode(code) {
      try {
  
        if (!window.currentCodeData || window.currentCodeData.code !== code) {
    
          const codeData = await nuiRet('getCodeDetails', { code: code });
          if (codeData && codeData.success) {
            window.currentCodeData = codeData.data;
                      } else {
            window.currentCodeData = null;
          }
        }
        
  
        showDeleteCodeModal(code);
      } catch (error) {
        console.error('Error showing delete modal:', error);
        toast('Error', 'Failed to show delete modal', 'error');
      }
    }
  
    function showDeleteCodeModal(code) {
  
      
  
      setText('deleteCodeText', code);
      setText('deleteCodeValue', code);
      
  
      if (window.currentCodeData) {
        const codeData = window.currentCodeData;
        setText('deleteCodeUses', codeData.uses || 'Unknown');
        setText('deleteCodeCreatedBy', codeData.created_by || 'Unknown');
      } else {
  
        const uses = doc.getElementById('viewUses')?.textContent || 'Unknown';
        const createdBy = doc.getElementById('viewCreatedBy')?.textContent || 'Unknown';
  
        setText('deleteCodeUses', uses);
        setText('deleteCodeCreatedBy', createdBy);
      }
      
  
      const modal = doc.getElementById('deleteCodeModal');
      if (modal) {
        modal.classList.remove('hidden');
      }
    }
  
    async function confirmDeleteCode() {
      try {
        const codeText = doc.getElementById('deleteCodeText')?.textContent;
        if (!codeText || codeText === 'Unknown') {
          toast('Error', 'No code specified for deletion', 'error');
          return;
        }
        
        await nui('deleteCode', { code: codeText });
        toast('Success', 'Code deleted successfully', 'success');
        
  
        const modal = doc.getElementById('deleteCodeModal');
        if (modal) {
          modal.classList.add('hidden');
        }
        
  
        refreshAll();
        showRoute('admin-dashboard');
      } catch (error) {
        console.error('Error deleting code:', error);
        toast('Error', 'Failed to delete code', 'error');
      }
    }
  
    function showDeleteTranscriptModal(session) {
      if (!session || !session.session_id) {
        toast('Error', 'Invalid transcript session', 'error');
        return;
      }
      
      const setText = (id, text) => {
        const el = doc.getElementById(id);
        if (el) el.textContent = text || 'Unknown';
      };
      
      setText('deleteTranscriptSessionId', session.session_id);
      setText('deleteTranscriptSessionIdValue', session.session_id);
      setText('deleteTranscriptPlayerName', session.player_name || 'Unknown');
      setText('deleteTranscriptMessageCount', session.message_count || 0);
      
      if (session.created_at) {
        const date = new Date(session.created_at);
        setText('deleteTranscriptCreatedAt', date.toLocaleString('en-US', {
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit'
        }));
      } else {
        setText('deleteTranscriptCreatedAt', 'Unknown');
      }
      
      const modal = doc.getElementById('deleteTranscriptModal');
      if (modal) {
        modal.classList.remove('hidden');
      }
    }
  
    async function confirmDeleteTranscript() {
      try {
        if (!window.currentTranscriptSession || !window.currentTranscriptSession.session_id) {
          toast('Error', 'No transcript session specified for deletion', 'error');
          return;
        }
        
        const sessionId = window.currentTranscriptSession.session_id;
        await nui('deleteTranscript', { sessionId: sessionId });
        toast('Success', 'Transcript deleted successfully', 'success');
        
        const deleteModal = doc.getElementById('deleteTranscriptModal');
        if (deleteModal) {
          deleteModal.classList.add('hidden');
        }
        
        const viewerModal = doc.getElementById('transcriptViewerModal');
        if (viewerModal) {
          viewerModal.classList.add('hidden');
        }
        
        // Refresh transcript list
        if (typeof window.loadAIChatSessions === 'function') {
          window.loadAIChatSessions();
        }
        
        // Clear stored session
        window.currentTranscriptSession = null;
      } catch (error) {
        console.error('Error deleting transcript:', error);
        toast('Error', 'Failed to delete transcript', 'error');
      }
    }
  
    function copyCode(code) {
      if (!code) {
        toast('Error', 'No code to copy', 'error');
        return;
      }
      
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(code).then(() => {
          toast('Success', 'Code copied to clipboard', 'success');
        }).catch(() => {
          fallbackCopyTextToClipboard(code);
        });
      } else {
        fallbackCopyTextToClipboard(code);
      }
    }
  
    function fallbackCopyTextToClipboard(text) {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.left = '-999999px';
      textArea.style.top = '-999999px';
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      
      try {
        document.execCommand('copy');
        toast('Success', 'Code copied to clipboard', 'success');
      } catch (err) {
        toast('Error', 'Failed to copy code', 'error');
      }
      
      document.body.removeChild(textArea);
    }
  
    async function loadCodeDetails(code) {
      try {
        const codeData = await nuiRet('getCodeDetails', { code: code });
        if (codeData && codeData.success) {
          populateCodeView(codeData.data);
        } else {
          toast('Error', 'Failed to load code details', 'error');
        }
      } catch (error) {
        console.error('Error loading code details:', error);
        toast('Error', 'Failed to load code details', 'error');
      }
    }
  
    async function openEditPage(code) {
      try {
        const codeData = await nuiRet('getCodeDetails', { code: code });
        if (codeData && codeData.success) {
          populateEditForm(codeData.data);
        } else {
          toast('Error', 'Failed to load code for editing', 'error');
        }
      } catch (error) {
        console.error('Error opening edit page:', error);
        toast('Error', 'Failed to load code for editing', 'error');
      }
    }
  
    function populateCodeView(codeData) {
  
      
      const code = codeData.code || 'Unknown';
      const uses = codeData.uses || 0;
      const maxUses = codeData.max_uses || 0;
      const perUserLimit = codeData.per_user_limit || 0;
      const createdBy = codeData.created_by || 'Unknown';
      const created = codeData.created_at || 'N/A';
      const expiry = codeData.expiry || 'Never';
  
      let rewards = [];
      if (codeData.items) {
        if (typeof codeData.items === 'string') {
          try {
            rewards = JSON.parse(codeData.items);
          } catch (e) {
            console.error('Error parsing rewards JSON:', e);
            rewards = [];
          }
        } else if (Array.isArray(codeData.items)) {
          rewards = codeData.items;
        }
      }
      
  
      
  
      window.currentCodeData = codeData;
      
  
      setText('viewCode', code);
      
  
      setText('viewUses', uses);
      setText('viewPerUser', perUserLimit > 0 ? perUserLimit : 'No limit');
      setText('viewCreator', createdBy);
      setText('viewCreated', formatDateForDisplay(created));
      setText('viewExpiry', formatDateForDisplay(expiry));

      try {
        const statusEl = doc.getElementById('viewCodeStatus');
        let statusText = 'Active';
        const nowTs = Date.now();
        const isExpired = expiry && expiry !== 'Never' && !isNaN(new Date(expiry).getTime()) && new Date(expiry).getTime() < nowTs;
        const isRedeemed = typeof uses === 'number' && uses <= 0;
        if (isRedeemed) statusText = 'Redeemed';
        else if (isExpired) statusText = 'Expired';
        if (statusEl) statusEl.textContent = statusText;
      } catch (_) {}
      
  
      const rewardsContainer = doc.getElementById('viewRewards');
  
      
      if (rewardsContainer) {
        if (rewards && Array.isArray(rewards) && rewards.length > 0) {
  
          let rewardsHTML = '';
          rewards.forEach(reward => {
            if (reward.item) {
              rewardsHTML += `
                <div class="reward-card">
                  <div class="reward-icon"><i class="fas fa-box"></i></div>
                  <div class="reward-amount">
                    <span class="reward-name">${reward.item}</span>
                    <span class="reward-value">${reward.amount || 1}x</span>
                  </div>
                </div>
              `;
            } else if (reward.money) {
              rewardsHTML += `
                <div class="reward-card">
                  <div class="reward-icon"><i class="fas fa-dollar-sign"></i></div>
                  <div class="reward-amount">
                    <span class="reward-name">${reward.option || 'cash'}</span>
                    <span class="reward-value">$${reward.amount || 0}</span>
                  </div>
                </div>
              `;
            } else if (reward.vehicle) {
              rewardsHTML += `
                <div class="reward-card">
                  <div class="reward-icon"><i class="fas fa-car"></i></div>
                  <div class="reward-amount">
                    <span class="reward-name">${reward.model || reward.vehicle}</span>
                    <span class="reward-value">Vehicle</span>
                  </div>
                </div>
              `;
            }
          });
          rewardsContainer.innerHTML = rewardsHTML;
        } else {
  
          rewardsContainer.innerHTML = '<div class="no-rewards">No rewards configured for this code</div>';
        }
      } else {
  
      }

      const redemptionsContainer = doc.getElementById('viewRedemptions');
      if (redemptionsContainer) {
        let redeemedBy = codeData.redeemed_by || {};
        if (typeof redeemedBy === 'string') {
          try {
            redeemedBy = JSON.parse(redeemedBy);
          } catch (_) {
            redeemedBy = {};
          }
        }

        const entries = Object.entries(redeemedBy);
        if (entries.length === 0) {
          redemptionsContainer.innerHTML = '<div class="redemption-item"><span class="redemption-player">No redemptions yet</span><span class="redemption-count">0</span></div>';
        } else {

          entries.sort((a, b) => (b[1] || 0) - (a[1] || 0));
          const html = entries.map(([userId, count]) => (
            `<div class="redemption-item">
               <span class="redemption-player">${userId}</span>
               <span class="redemption-count">${count}</span>
             </div>`
          )).join('');
          redemptionsContainer.innerHTML = html;
        }
      }
    }
  
    function populateEditForm(codeData) {
      const code = codeData.code || '';
      const uses = codeData.uses || 1;
      const expiry = codeData.expiry || 'Never';
      const perUserLimit = codeData.per_user_limit || 1;
      let rewards = codeData.items || [];
      
      window.editOriginalCode = code;
      
  
      
  
      if (typeof rewards === 'string') {
        try {
          rewards = JSON.parse(rewards);
  
        } catch (error) {
          console.error('Failed to parse rewards:', error);
          rewards = [];
        }
      }
      
  
      setVal('editCode', code);
      setVal('editUses', uses);
      setVal('editPerUser', perUserLimit);
      const restrictEnabled = codeData.restricted_to_enabled === true || codeData.restricted_to_enabled === 1;
      const editRestrictToggle = doc.getElementById('editRestrictToPlayerEnabled');
      const editIdentifierType = doc.getElementById('editPlayerIdentifierType');
      const editIdentifierValue = doc.getElementById('editPlayerIdentifierValue');
      if (editRestrictToggle) editRestrictToggle.checked = restrictEnabled;
      if (editIdentifierType) editIdentifierType.value = codeData.restricted_to_type || 'citizenid';
      if (editIdentifierValue) editIdentifierValue.value = codeData.restricted_to_value || '';
      
  
      if (expiry && expiry !== 'Never') {
        try {
          let date;
  
          if (typeof expiry === 'string' && /^\d+$/.test(expiry)) {
            date = new Date(parseInt(expiry));
          } else {
            date = new Date(expiry);
          }
          
          if (!isNaN(date.getTime())) {
  
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            const hours = String(date.getHours()).padStart(2, '0');
            const minutes = String(date.getMinutes()).padStart(2, '0');
            const formattedDate = `${year}-${month}-${day}T${hours}:${minutes}`;
            setVal('editExpiry', formattedDate);
  
          } else {
            setVal('editExpiry', '');
          }
        } catch (error) {
          console.error('Error formatting expiry date:', error);
          setVal('editExpiry', '');
        }
      } else {
        setVal('editExpiry', '');
      }
      
  
      window.editRewards = [];
      
  
      if (rewards && Array.isArray(rewards) && rewards.length > 0) {
        rewards.forEach(reward => {
          window.editRewards.push(reward);
        });
  
      }
      
      updateEditRewardsTable();
    }
  
    function addEditReward() {
      const type = doc.getElementById('editRewardType')?.value || 'item';
      const item = doc.getElementById('editRewardName')?.value?.trim() || '';
      const label = doc.getElementById('editRewardLabel')?.value?.trim() || '';
      const amount = parseInt(doc.getElementById('editRewardAmount')?.value || '1');

      if (!item && type !== 'money') {
        toast('Error', 'Please enter a reward item', 'error');
        return;
      }
      
      const reward = { type: type, amount: amount };
      
      if (type === 'item') {
        reward.item = item;
        if (label) reward.label = label;
      } else if (type === 'money') {
        reward.money = amount;
      } else if (type === 'vehicle') {
        reward.vehicle = item;
        reward.model = item;
        if (label) reward.label = label;
      }
      
      if (!window.editRewards) window.editRewards = [];
      window.editRewards.push(reward);
      updateEditRewardsTable();
      
      setVal('editRewardName', '');
      setVal('editRewardLabel', '');
      setVal('editRewardAmount', '1');
    }
  
    function removeEditReward(index) {
      if (window.editRewards && window.editRewards[index]) {
        window.editRewards.splice(index, 1);
        updateEditRewardsTable();
      }
    }
  
    function updateEditRewardsTable() {
      const table = doc.getElementById('editRewardsTable');
      if (!table) return;
      
      if (!window.editRewards || window.editRewards.length === 0) {
        table.innerHTML = '<tr><td colspan="4" class="text-center">No rewards</td></tr>';
        return;
      }
      
      let html = '';
      window.editRewards.forEach((reward, index) => {
        let description = '';
        if (reward.item) {
          description = `${reward.amount}x ${formatRewardDisplayName(reward.item, reward.label)}`;
        } else if (reward.money) {
          description = `$${reward.amount}`;
        } else if (reward.vehicle) {
          description = `Vehicle: ${formatRewardDisplayName(reward.model || reward.vehicle, reward.label)}`;
        } else {
          description = 'Unknown reward';
        }
        
        html += `
          <tr>
            <td>${description}</td>
            <td>${reward.amount}</td>
            <td>${reward.type || 'item'}</td>
            <td>
              <button class="btn btn-xs btn-danger" onclick="removeEditReward(${index})">Remove</button>
            </td>
          </tr>
        `;
      });
      
      table.innerHTML = html;
    }
  
    async function saveEditChanges() {
      const originalCode = window.editOriginalCode || '';
      const newCode = doc.getElementById('editCode')?.value || '';
      const uses = parseInt(doc.getElementById('editUses')?.value || '1');
      const expiry = doc.getElementById('editExpiry')?.value || '';
      const perUserLimit = parseInt(doc.getElementById('editPerUser')?.value || '1');
      const rewards = window.editRewards || [];
      const restrictEnabled = doc.getElementById('editRestrictToPlayerEnabled')?.checked === true;
      const restrictionType = doc.getElementById('editPlayerIdentifierType')?.value || null;
      const restrictionValue = doc.getElementById('editPlayerIdentifierValue')?.value?.trim() || null;
      
      if (!originalCode || !newCode) {
        toast('Error', 'Please enter a code', 'error');
        return;
      }
      
      let expiryValue = null;
      if (expiry && expiry !== 'Never' && expiry !== '') {
        const expiryDate = new Date(expiry);
        if (!isNaN(expiryDate.getTime())) {
          const year = expiryDate.getFullYear();
          const month = String(expiryDate.getMonth() + 1).padStart(2, '0');
          const day = String(expiryDate.getDate()).padStart(2, '0');
          const hours = String(expiryDate.getHours()).padStart(2, '0');
          const minutes = String(expiryDate.getMinutes()).padStart(2, '0');
          const seconds = String(expiryDate.getSeconds()).padStart(2, '0');
          expiryValue = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
        }
      }
      
      try {
        await nui('updateCode', {
          originalCode: originalCode,
          newCode: newCode,
          uses: uses,
          expiry: expiryValue,
          itemsJson: JSON.stringify(rewards),
          perUserLimit: perUserLimit,
          playerRestriction: {
            enabled: restrictEnabled,
            type: restrictionType,
            value: restrictionValue
          }
        });
        
        toast('Success', 'Code updated successfully', 'success');
        showRoute('admin-codes');
        refreshAll();
      } catch (error) {
        console.error('Error updating code:', error);
        toast('Error', 'Failed to update code', 'error');
      }
    }
  
    function resetEditCode() {
      setVal('editCode', '');
      setVal('editUses', '1');
      setVal('editExpiry', 'Never');
      window.editRewards = [];
      updateEditRewardsTable();
    }
  
    function copyEditCode() {
      const code = doc.getElementById('editCode')?.value?.trim();
      if (code) {
        copyCode(code);
      } else {
        toast('Error', 'No code to copy', 'error');
      }
    }
  
  
    
    let currentRedeemCode = '';
    let selectedAccount = 'cash';
    
    function initRedeemUI() {
      const redeemInput = doc.getElementById('redeemInput');
      const redeemBtn = doc.getElementById('redeemBtn');
      const moneyOptions = doc.getElementById('moneyOptions');
      const moneyBtns = doc.querySelectorAll('.money-btn');
      
  
      redeemInput?.addEventListener('input', (e) => {
        currentRedeemCode = e.target.value.trim();
        updateRedeemButton();
        
  
        if (currentRedeemCode.length > 0) {
          checkCodeForMoneyRewards(currentRedeemCode);
        } else {
          hideMoneyOptions();
        }
      });
      
  
      redeemBtn?.addEventListener('click', () => {
        if (currentRedeemCode && !redeemBtn.disabled) {
          submitRedeemCode();
        }
      });
      
  
      moneyBtns.forEach(btn => {
        btn.addEventListener('click', () => {
          moneyBtns.forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
          selectedAccount = btn.dataset.account;
        });
      });
      
  
      redeemInput?.addEventListener('keypress', (e) => {
        if (e.key === 'Enter' && currentRedeemCode && !redeemBtn.disabled) {
          submitRedeemCode();
        }
      });
    }
    
    function updateRedeemButton() {
      const redeemBtn = doc.getElementById('redeemBtn');
      if (redeemBtn) {
        redeemBtn.disabled = currentRedeemCode.length === 0;
      }
    }
    
    function checkCodeForMoneyRewards(code) {
  
      
  
      const isValidCodeFormat = code.length >= 6 && (
        code.includes('-') ||
        code.match(/^[A-Za-z0-9]{6,}$/)
      );
      
  
      
      if (!isValidCodeFormat) {
  
        hideMoneyOptions();
        return;
      }
      
  
      
  
      fetch(`https://${PRN}/checkCodeRewards`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ code: code })
      })
      .then(response => response.json())
      .then(result => {
  
        if (result.success && result.hasMoneyRewards) {
          showMoneyOptions();
        } else {
          hideMoneyOptions();
        }
      })
      .catch(error => {
        console.error('[DEBUG] Error checking code rewards:', error);
        hideMoneyOptions();
      });
    }
    
    function showMoneyOptions() {
      const moneyOptions = doc.getElementById('moneyOptions');
      if (moneyOptions) {
        moneyOptions.classList.remove('hidden');
      }
    }
    
    function hideMoneyOptions() {
      const moneyOptions = doc.getElementById('moneyOptions');
      if (moneyOptions) {
        moneyOptions.classList.add('hidden');
      }
    }

    function formatRewardDisplayName(name, label) {
      if (label && String(label).trim()) return String(label).trim();
      const raw = String(name || '').replace(/_/g, ' ').trim();
      if (!raw) return '';
      return raw.replace(/\b\w/g, c => c.toUpperCase());
    }

    function getItemRewardIcon(name) {
      const n = String(name || '').toLowerCase().replace(/_/g, ' ');
      if (/\b(water|drink|coffee|beer|whiskey|juice|soda|cola)\b/.test(n)) return 'fa-tint';
      if (/\b(sandwich|burger|bread|food|meat|fish|pizza|taco|snack|donut|apple)\b/.test(n)) return 'fa-utensils';
      if (/\b(weapon|pistol|rifle|gun|ammo|bullet|knife)\b/.test(n)) return 'fa-crosshairs';
      if (/\b(phone|radio|tablet|laptop|mobile)\b/.test(n)) return 'fa-mobile-alt';
      if (/\b(key|lockpick)\b/.test(n)) return 'fa-key';
      if (/\b(med|bandage|pill|health|firstaid|morphine)\b/.test(n)) return 'fa-medkit';
      if (/\b(fuel|gas|petrol|jerry)\b/.test(n)) return 'fa-gas-pump';
      if (/\b(diamond|gold|jewel|gem)\b/.test(n)) return 'fa-gem';
      return 'fa-cube';
    }

    function buildRedeemSuccessHTML(rewards) {
      if (!rewards) return '';
      const sections = [];

      const categoryHeader = (icon, label) => `
        <div class="redeem-success-category-label">
          <span class="redeem-success-category-icon"><i class="fas ${icon}"></i></span>
          <span class="redeem-success-category-text">${label}</span>
        </div>
      `;

      const listIcon = (iconClass) => `<span class="redeem-success-list-icon"><i class="fas ${iconClass}"></i></span>`;

      if (rewards.money != null && rewards.money > 0) {
        sections.push(`
          <div class="redeem-success-category">
            ${categoryHeader('fa-dollar-sign', 'Money')}
            <div class="redeem-success-money-value">${Number(rewards.money).toLocaleString()}</div>
          </div>
        `);
      }

      if (Array.isArray(rewards.items) && rewards.items.length > 0) {
        const itemsHTML = rewards.items.map(item => {
          const amount = item.amount || 1;
          const name = escapeHtml(formatRewardDisplayName(item.name || item.item, item.label));
          const icon = getItemRewardIcon(item.name || item.item);
          return `<li>${listIcon(icon)}<span>${amount} ${name}</span></li>`;
        }).join('');
        sections.push(`
          <div class="redeem-success-category">
            ${categoryHeader('fa-box', 'Items')}
            <ul class="redeem-success-list">${itemsHTML}</ul>
          </div>
        `);
      }

      if (Array.isArray(rewards.vehicles) && rewards.vehicles.length > 0) {
        const vehiclesHTML = rewards.vehicles.map(vehicle => {
          const vehicleName = typeof vehicle === 'object' ? (vehicle.model || vehicle.name) : vehicle;
          const vehicleLabel = typeof vehicle === 'object' ? vehicle.label : '';
          const name = formatRewardDisplayName(vehicleName, vehicleLabel);
          return `<li>${listIcon('fa-car')}<span>${escapeHtml(name)}</span></li>`;
        }).join('');
        sections.push(`
          <div class="redeem-success-category">
            ${categoryHeader('fa-car', 'Vehicles')}
            <ul class="redeem-success-list">${vehiclesHTML}</ul>
          </div>
        `);
      }

      return sections.join('');
    }

    function showRedeemSuccess(rewards) {
      const redeemHeader = doc.querySelector('#route-player .redeem-header');
      const redeemForm = doc.querySelector('#route-player .redeem-form');
      const successView = doc.getElementById('redeemSuccessView');
      const successRewards = doc.getElementById('redeemSuccessRewards');

      if (redeemHeader) redeemHeader.classList.add('redeem-form-hidden');
      if (redeemForm) redeemForm.classList.add('redeem-form-hidden');
      if (successRewards) successRewards.innerHTML = buildRedeemSuccessHTML(rewards);
      if (successView) successView.classList.remove('hidden');
    }

    function resetRedeemSuccessView() {
      const redeemHeader = doc.querySelector('#route-player .redeem-header');
      const redeemForm = doc.querySelector('#route-player .redeem-form');
      const successView = doc.getElementById('redeemSuccessView');
      const successRewards = doc.getElementById('redeemSuccessRewards');

      if (redeemHeader) redeemHeader.classList.remove('redeem-form-hidden');
      if (redeemForm) redeemForm.classList.remove('redeem-form-hidden');
      if (successView) successView.classList.add('hidden');
      if (successRewards) successRewards.innerHTML = '';
    }
    
    function submitRedeemCode() {
      const redeemBtn = doc.getElementById('redeemBtn');
      const btnText = redeemBtn.querySelector('.btn-text');
      const btnIcon = redeemBtn.querySelector('.btn-icon');
      const app = doc.getElementById('app');
      
  
      redeemBtn.disabled = true;
      btnText.textContent = 'Redeeming...';
      btnIcon.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
      
      const submitTitle = typeof t === 'function' ? t('UI_TOAST_SUBMITTING_CODE') : 'Submitting Code';
      const submitMessage = typeof t === 'function' ? t('UI_TOAST_SUBMITTING_CODE_MESSAGE') : 'Validating your code...';
      toast(submitTitle, submitMessage, 'info');
      
      if (app) {
        app.classList.add('app-shaking');
      }
      
      const redeemData = {
        code: currentRedeemCode,
        account: selectedAccount
      };
      
      const shakeDelayMs = 5000;
      setTimeout(() => {
        fetch(`https://${PRN}/playerRedeem`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(redeemData)
        })
        .then(response => response.json())
        .then(result => {
          if (app) {
            app.classList.remove('app-shaking');
          }
          
          if (result.success === true || result.success) {
            showRedeemSuccess(result.rewards);

            const redeemInput = doc.getElementById('redeemInput');
            if (redeemInput) {
              redeemInput.value = '';
              currentRedeemCode = '';
            }
            hideMoneyOptions();
            updateRedeemButton();

            setTimeout(() => {
              resetRedeemSuccessView();
              redeemBtn.disabled = false;
              btnText.textContent = 'Redeem Code';
              btnIcon.innerHTML = '→';
              fetch(`https://${PRN}/close`, { method: 'POST' });
            }, 3000);
          } else {
            redeemBtn.disabled = false;
            btnText.textContent = 'Redeem Code';
            btnIcon.innerHTML = '→';
            const errorMessage = result.error || 'Invalid code or code has expired.';
            toast('Redemption Failed', errorMessage, 'error');
          }
        })
        .catch(error => {
          console.error('Redemption error:', error);
          
          if (app) {
            app.classList.remove('app-shaking');
          }
          
          redeemBtn.disabled = false;
          btnText.textContent = 'Redeem Code';
          btnIcon.innerHTML = '→';
          toast('Connection Error', 'Failed to redeem code. Please try again.', 'error');
        });
      }, shakeDelayMs);
    }
  
    function setupAIVisibility() {
      const aiChatSettingsBtn = doc.getElementById('aiChatSettingsBtn');
      const aiChatSettingsSection = doc.getElementById('aiChatSettingsSection');
      const aiNavItem = doc.querySelector('.nav-item[data-route="ai-generation"]');
      const aiRoute = doc.getElementById('route-ai-generation');
      const transcriptsBtn = doc.getElementById('transcriptsBtn');
      const transcriptsSection = doc.getElementById('transcriptsSection');
      const transcriptViewerModal = doc.getElementById('transcriptViewerModal');
      const deleteTranscriptModal = doc.getElementById('deleteTranscriptModal');
      const ownerCanManage = isOwnerUser;
      
      if (!aiEnabled) {
        if (aiNavItem) {
          aiNavItem.classList.add('hidden');
        }
        if (aiRoute) {
          aiRoute.classList.remove('route-active');
          aiRoute.classList.add('hidden');
        }
        if (currentRoute === 'ai-generation') {
          showRoute('admin-dashboard');
        }
        if (aiChatSettingsBtn) {
          aiChatSettingsBtn.classList.toggle('hidden', !ownerCanManage);
        }
        if (aiChatSettingsSection && !ownerCanManage && !aiChatSettingsSection.classList.contains('hidden')) {
          showSettingsSection('displaySettingsSection');
        }
        if (aiChatSettingsSection && !ownerCanManage) {
          aiChatSettingsSection.classList.add('hidden');
        }
        if (transcriptsBtn) {
          transcriptsBtn.classList.add('hidden');
        }
        if (transcriptsSection) {
          transcriptsSection.classList.add('hidden');
        }
        if (transcriptViewerModal) {
          transcriptViewerModal.classList.add('hidden');
        }
        if (deleteTranscriptModal) {
          deleteTranscriptModal.classList.add('hidden');
        }
      } else {
        if (aiNavItem) {
          aiNavItem.classList.remove('hidden');
        }
        if (aiRoute) {
          aiRoute.classList.remove('hidden');
        }
        if (aiChatSettingsBtn) {
          aiChatSettingsBtn.classList.remove('hidden');
        }
        if (transcriptsBtn) {
          transcriptsBtn.classList.remove('hidden');
        }
      }
      setupOwnerOnlyUI();
    }
  
    document.addEventListener('DOMContentLoaded', async () => {
      await initializeLocale();
      initTheme();
      aiEnabled = true;
      try {
        const config = await nuiRet('getServerConfig', {});
        if (config && typeof config.aiEnabled !== 'undefined') {
          aiEnabled = !!config.aiEnabled;
        }
        if (config && config.version) {
          updateVersionPanel(config.version, false);
        } else {
          loadVersionInfo(false);
        }
      } catch (_) {
        aiEnabled = true;
        loadVersionInfo(false);
      }
      setupAIVisibility();
      
      requestAnimationFrame(() => {
        const savedColorTheme = localStorage.getItem('midnight_redeem_theme') || 'default';
        if (typeof applyColorTheme === 'function') {
          applyColorTheme(savedColorTheme);
        }
        
        loadCustomColors();
        initColorCustomization();
      });
      
      applyLocale();

      themeToggle?.addEventListener('click', () => {
        const currentTheme = localStorage.getItem('mr_theme') || 'dark';
        const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
        localStorage.setItem('mr_theme', newTheme);
        applyTheme();
      });
      
      doc.querySelectorAll('.nav-item').forEach(btn => {
        btn.addEventListener('click', () => showRoute(btn.dataset.route));
      });

      const talkToShadowBtn = doc.getElementById('talkToShadowBtn');
      const shadowChatInput = doc.getElementById('shadowChatInput');
      const shadowSendMessageBtn = doc.getElementById('shadowSendMessage');
      talkToShadowBtn?.addEventListener('click', async () => {
        const rulesPage = doc.getElementById('shadowRulesPage');
        const chatPage = doc.getElementById('shadowChatPage');
        if (rulesPage) rulesPage.classList.add('hidden');
        if (chatPage) chatPage.classList.remove('hidden');
        let sessionResult = null;
        try {
          sessionResult = await nuiRet('createShadowChatSession', {});
          if (sessionResult?.success && sessionResult?.sessionId) {
            currentShadowSessionId = sessionResult.sessionId;
          } else {
            currentShadowSessionId = null;
          }
        } catch (_) {
          currentShadowSessionId = null;
        }
        const messagesHost = doc.getElementById('shadowChatMessages');
        if (messagesHost) {
          Array.from(messagesHost.children).forEach((child) => {
            if (child.id !== 'shadowTypingIndicator') child.remove();
          });
          const typing = doc.getElementById('shadowTypingIndicator');
          if (typing) typing.classList.add('hidden');
          clearShadowThinkingStatus();
        }
        shadowConversationHistory = [];
        const welcomeText = (sessionResult?.welcome) || t('UI_SHADOW_INITIAL_GREETING');
        addShadowMessage(welcomeText, false);
      });

      shadowSendMessageBtn?.addEventListener('click', () => {
        const msg = shadowChatInput?.value?.trim() || '';
        if (!msg) return;
        shadowChatInput.value = '';
        sendShadowMessage(msg);
      });
      shadowChatInput?.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          const msg = shadowChatInput?.value?.trim() || '';
          if (!msg) return;
          shadowChatInput.value = '';
          sendShadowMessage(msg);
        }
      });

      const saved = localStorage.getItem('mr_locale');
      if (saved && saved !== currentLocale) {
        loadLocale(saved).then(success => {
          if (success) {
            applyLocale();
            if (currentRoute) {
              showRoute(currentRoute);
            }
          }
        }).catch(() => {
        });
      }

      try { 
        showRoute(currentRoute);
      } catch (err) {
        console.error('Error showing initial route:', err);
      }
      
  
      doc.getElementById('closeBtn')?.addEventListener('click', () => {
        fetch(`https://${PRN}/close`, { method: 'POST' });
      });
      
  
      doc.getElementById('refreshBtn')?.addEventListener('click', () => {
  
        showRoute('admin-dashboard');
        loadDashboard();
        loadUserPermissions();
        
        window.allCodes = [];
        wizardRewards = [];
        currentWizardStep = 1;
        
        // Reset settings page state
        resetSettingsPage();
        
        toast('Refresh', 'All data refreshed and returned to dashboard', 'success');
      });
      
  
      doc.getElementById('openWizardBtn')?.addEventListener('click', openWizardModal);
      doc.getElementById('wizardModalClose')?.addEventListener('click', hideWizardModal);
      doc.getElementById('wizardPrev')?.addEventListener('click', wizardPreviousStep);
      doc.getElementById('wizardNext')?.addEventListener('click', wizardNextStep);
      doc.getElementById('wizardGenerate')?.addEventListener('click', generateWizardCode);
      
  
      doc.getElementById('deleteCodeModalClose')?.addEventListener('click', () => {
        const modal = doc.getElementById('deleteCodeModal');
        if (modal) modal.classList.add('hidden');
      });
      doc.getElementById('deleteCodeCancel')?.addEventListener('click', () => {
        const modal = doc.getElementById('deleteCodeModal');
        if (modal) modal.classList.add('hidden');
      });
      doc.getElementById('deleteCodeConfirm')?.addEventListener('click', confirmDeleteCode);
      
      doc.getElementById('purgeCodesModalClose')?.addEventListener('click', () => {
        const modal = doc.getElementById('purgeCodesModal');
        if (modal) modal.classList.add('hidden');
        window.pendingPurgeAction = null;
      });
      doc.getElementById('purgeCodesCancel')?.addEventListener('click', () => {
        const modal = doc.getElementById('purgeCodesModal');
        if (modal) modal.classList.add('hidden');
        window.pendingPurgeAction = null;
      });
      doc.getElementById('purgeCodesConfirm')?.addEventListener('click', confirmPurge);
      
  
      doc.getElementById('editRoleModalClose')?.addEventListener('click', hideEditRoleModal);
      doc.getElementById('editRoleCancel')?.addEventListener('click', hideEditRoleModal);
      doc.getElementById('editRoleConfirm')?.addEventListener('click', updateUserRole);
      
      doc.getElementById('copyCustomCode')?.addEventListener('click', copyCustomCode);
      doc.getElementById('copySummaryCode')?.addEventListener('click', copySummaryCode);
      doc.getElementById('wizardAddReward')?.addEventListener('click', addWizardReward);
      doc.getElementById('saveTemplate')?.addEventListener('click', saveWizardTemplate);
      
      const wizardRewardType = doc.getElementById('wizardRewardType');
      if (wizardRewardType) {
        wizardRewardType.addEventListener('change', () => syncManualRewardFields('wizard'));
        syncManualRewardFields('wizard');
      }

      const editRewardType = doc.getElementById('editRewardType');
      if (editRewardType) {
        editRewardType.addEventListener('change', () => syncManualRewardFields('edit'));
        syncManualRewardFields('edit');
      }

      doc.querySelectorAll('.expiry-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          doc.querySelectorAll('.expiry-btn').forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
          
          const expiry = btn.dataset.expiry;
          const relativeExpirySection = doc.getElementById('relative-expiry-section');
          const specificExpirySection = doc.getElementById('specific-expiry-section');
          if (relativeExpirySection) relativeExpirySection.classList.add('hidden');
          if (specificExpirySection) specificExpirySection.classList.add('hidden');
          
          if (expiry === 'relative') {
            if (relativeExpirySection) relativeExpirySection.classList.remove('hidden');
          } else if (expiry === 'specific') {
            if (specificExpirySection) specificExpirySection.classList.remove('hidden');
          }
        });
      });
      
  
      doc.getElementById('bulkGenerateBtn')?.addEventListener('click', openBulkGenerateModal);
      doc.getElementById('bulkGenerateModalClose')?.addEventListener('click', hideBulkGenerateModal);
      doc.getElementById('bulkGenerateCancel')?.addEventListener('click', hideBulkGenerateModal);
      doc.getElementById('bulkGenerateConfirm')?.addEventListener('click', generateBulkCodes);
  
  
  
  
      doc.querySelectorAll('.expiry-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          doc.querySelectorAll('.expiry-btn').forEach(b => b.classList.remove('active'));
          btn.classList.add('active');
          
          const expiryMethod = btn.dataset.expiry;
          doc.querySelectorAll('.expiry-section').forEach(section => {
            section.classList.add('hidden');
          });
          
          const targetSection = doc.getElementById(`${expiryMethod}ExpirySection`);
          if (targetSection) {
            targetSection.classList.remove('hidden');
          }
        });
      });
      
  
      setupWizardSelectors();
      initializeWizard();
      
  
      window.removeWizardReward = removeWizardReward;
      window.openWizardModal = openWizardModal;
      window.hideWizardModal = hideWizardModal;
      window.wizardPreviousStep = wizardPreviousStep;
      window.wizardNextStep = wizardNextStep;
      window.generateWizardCode = generateWizardCode;
      window.addWizardReward = addWizardReward;
      window.saveWizardTemplate = saveWizardTemplate;
      
  
      window.openBulkGenerateModal = openBulkGenerateModal;
      window.hideBulkGenerateModal = hideBulkGenerateModal;
      window.generateBulkCodes = generateBulkCodes;
      
  
      window.viewCode = viewCode;
      window.editCode = editCode;
      window.deleteCode = deleteCode;
      
  
      showRoute('admin-dashboard');
      
       doc.getElementById('displaySettingsBtn')?.addEventListener('click', () => {
         showSettingsSection('displaySettingsSection');
       });

      doc.getElementById('refreshVersionBtn')?.addEventListener('click', () => {
        loadVersionInfo(true);
      });
  
      doc.getElementById('permissionsBtn')?.addEventListener('click', () => {
         showSettingsSection('permissionsSection');
      });
      
      doc.getElementById('codeSettingsBtn')?.addEventListener('click', () => {
        showSettingsSection('codeSettingsSection');
      });
      
      doc.getElementById('aiChatSettingsBtn')?.addEventListener('click', () => {
        if (!aiEnabled && !isOwnerUser) {
          return;
        }
        showSettingsSection('aiChatSettingsSection');
        if (aiEnabled) {
          setTimeout(() => {
            loadAIChatSessions();
          }, 100);
        } else if (isOwnerUser) {
          showAIChatSubsection('chatSettingsSection');
        }
      });
      
      // AI Chat Settings subsection handlers
      doc.getElementById('transcriptsBtn')?.addEventListener('click', () => {
        if (!aiEnabled) {
          return;
        }
        showAIChatSubsection('transcriptsSection');
        loadAIChatSessions();
      });
      
      doc.getElementById('chatSettingsBtn')?.addEventListener('click', () => {
        showAIChatSubsection('chatSettingsSection');
      });

      doc.getElementById('runtimeConfigBtn')?.addEventListener('click', () => {
        showSettingsSection('runtimeConfigSection');
      });

      doc.querySelectorAll('[data-config-tab]').forEach(btn => {
        btn.addEventListener('click', () => {
          loadRuntimeConfigTab(btn.dataset.configTab);
        });
      });

      doc.getElementById('saveRuntimeConfigBtn')?.addEventListener('click', () => {
        saveRuntimeConfigTab();
      });

      doc.getElementById('resetRuntimeConfigBtn')?.addEventListener('click', () => {
        resetRuntimeConfigTab();
      });

      doc.getElementById('saveAIChatSettingsBtn')?.addEventListener('click', () => {
        saveAIChatSettings();
      });

      doc.getElementById('runTranscriptCleanupBtn')?.addEventListener('click', async () => {
        if (!isOwnerUser) return;
        try {
          const result = await nuiRet('runTranscriptCleanup', {});
          if (result?.success) {
            const deleted = Number(result.deleted || 0);
            toast(
              t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings',
              deleted > 0
                ? (t('UI_SETTINGS_CHAT_CLEANUP_DONE') || 'Transcript cleanup completed.')
                : (t('UI_SETTINGS_CHAT_CLEANUP_NONE') || 'No old transcripts matched the retention policy.'),
              'success'
            );
          } else {
            toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', result?.error || 'Cleanup failed.', 'error');
          }
        } catch (error) {
          toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', 'Cleanup failed.', 'error');
        }
      });

      doc.getElementById('resetAIChatRateLimitsBtn')?.addEventListener('click', async () => {
        if (!isOwnerUser) return;
        try {
          const result = await nuiRet('resetAIChatRateLimits', {});
          if (result?.success) {
            toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', t('UI_SETTINGS_CHAT_RATE_LIMITS_RESET') || 'Shadow rate limits reset.', 'success');
          } else {
            toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', result?.error || 'Failed to reset rate limits.', 'error');
          }
        } catch (error) {
          toast(t('UI_SETTINGS_CHAT_SETTINGS_TITLE') || 'Chat Settings', 'Failed to reset rate limits.', 'error');
        }
      });

      const clearAllTranscriptsModal = doc.getElementById('clearAllTranscriptsModal');
      const closeClearAllTranscriptsModal = () => clearAllTranscriptsModal?.classList.add('hidden');

      doc.getElementById('clearAllTranscriptsBtn')?.addEventListener('click', () => {
        if (!isOwnerUser) return;
        clearAllTranscriptsModal?.classList.remove('hidden');
      });
      doc.getElementById('clearAllTranscriptsModalClose')?.addEventListener('click', closeClearAllTranscriptsModal);
      doc.getElementById('clearAllTranscriptsCancel')?.addEventListener('click', closeClearAllTranscriptsModal);
      doc.getElementById('clearAllTranscriptsConfirm')?.addEventListener('click', async () => {
        if (!isOwnerUser) return;
        try {
          const result = await nuiRet('clearAllTranscripts', {});
          closeClearAllTranscriptsModal();
          if (result?.success) {
            toast(t('UI_SETTINGS_CHAT_CLEAR_ALL_TITLE') || 'Clear All Transcripts', t('UI_SETTINGS_CHAT_ALL_CLEARED') || 'All transcripts cleared.', 'success');
            loadAIChatSessions();
          } else {
            toast(t('UI_SETTINGS_CHAT_CLEAR_ALL_TITLE') || 'Clear All Transcripts', result?.error || 'Failed to clear transcripts.', 'error');
          }
        } catch (error) {
          closeClearAllTranscriptsModal();
          toast(t('UI_SETTINGS_CHAT_CLEAR_ALL_TITLE') || 'Clear All Transcripts', 'Failed to clear transcripts.', 'error');
        }
      });
      
      // Transcript search and filter handlers
      doc.getElementById('transcriptSessionIdSearch')?.addEventListener('input', () => {
        filterTranscripts();
      });
      
      doc.getElementById('transcriptPlayerSearch')?.addEventListener('input', () => {
        filterTranscripts();
      });
      
      doc.getElementById('transcriptDateFrom')?.addEventListener('change', () => {
        filterTranscripts();
      });
      
      doc.getElementById('transcriptDateTo')?.addEventListener('change', () => {
        filterTranscripts();
      });
      
      doc.getElementById('transcriptSortOrder')?.addEventListener('change', () => {
        filterTranscripts();
      });
      
      doc.getElementById('clearTranscriptSessionIdSearch')?.addEventListener('click', () => {
        const input = doc.getElementById('transcriptSessionIdSearch');
        if (input) {
          input.value = '';
          filterTranscripts();
        }
      });
      
      doc.getElementById('clearTranscriptPlayerSearch')?.addEventListener('click', () => {
        const input = doc.getElementById('transcriptPlayerSearch');
        if (input) {
          input.value = '';
          filterTranscripts();
        }
      });
      
      doc.getElementById('clearTranscriptFilters')?.addEventListener('click', () => {
        const sessionIdInput = doc.getElementById('transcriptSessionIdSearch');
        const playerInput = doc.getElementById('transcriptPlayerSearch');
        const dateFromInput = doc.getElementById('transcriptDateFrom');
        const dateToInput = doc.getElementById('transcriptDateTo');
        const sortOrderSelect = doc.getElementById('transcriptSortOrder');
        
        if (sessionIdInput) sessionIdInput.value = '';
        if (playerInput) playerInput.value = '';
        if (dateFromInput) dateFromInput.value = '';
        if (dateToInput) dateToInput.value = '';
        if (sortOrderSelect) sortOrderSelect.value = 'newest';
        
        filterTranscripts();
      });
      
      doc.getElementById('applyTranscriptFilters')?.addEventListener('click', () => {
        filterTranscripts();
      });
      
      doc.getElementById('refreshTranscripts')?.addEventListener('click', () => {
        loadAIChatSessions();
      });
      
      function setPurgeButtonLoading(buttonId, loading) {
        const btn = doc.getElementById(buttonId);
        if (btn) {
          const btnText = btn.querySelector('.btn-text');
          const icon = btn.querySelector('i');
          if (loading) {
            btn.disabled = true;
            if (btnText) btnText.textContent = 'Purging...';
            if (icon) icon.className = 'fas fa-spinner fa-spin';
            btn.style.opacity = '0.6';
            btn.style.cursor = 'not-allowed';
          } else {
            btn.disabled = false;
            if (btnText) {
              let localeKey = 'UI_SETTINGS_PURGE_DAY';
              if (buttonId === 'purgeWeekBtn') localeKey = 'UI_SETTINGS_PURGE_WEEK';
              else if (buttonId === 'purgeMonthBtn') localeKey = 'UI_SETTINGS_PURGE_MONTH';
              else if (buttonId === 'purgeAllBtn') localeKey = 'UI_SETTINGS_PURGE_ALL';
              btnText.textContent = t(localeKey);
            }
            if (icon) icon.className = 'fas fa-trash';
            btn.style.opacity = '1';
            btn.style.cursor = 'pointer';
          }
        }
      }
      
      function showPurgeModal(period, buttonId) {
        const includeActive = doc.getElementById('purgeIncludeActive')?.checked || false;
        let periodText = 'Unknown';
        if (period === 'day') periodText = t('UI_PURGE_PERIOD_DAY');
        else if (period === 'week') periodText = t('UI_PURGE_PERIOD_WEEK');
        else if (period === 'month') periodText = t('UI_PURGE_PERIOD_MONTH');
        else if (period === 'all') periodText = t('UI_PURGE_PERIOD_ALL');
        const activeText = includeActive ? t('UI_GENERIC_YES') : t('UI_GENERIC_NO');
        
        setText('purgePeriodText', periodText);
        setText('purgeIncludeActiveText', activeText);
        
        window.pendingPurgeAction = { period, buttonId, includeActive };
        
        const modal = doc.getElementById('purgeCodesModal');
        if (modal) {
          modal.classList.remove('hidden');
        }
      }
      
      async function confirmPurge() {
        const action = window.pendingPurgeAction;
        if (!action) {
          toast('Error', 'No purge action specified', 'error');
          return;
        }
        
        const { period, buttonId, includeActive } = action;
        let periodText = 'Unknown';
        if (period === 'day') periodText = '1 day';
        else if (period === 'week') periodText = '1 week';
        else if (period === 'month') periodText = '1 month';
        else if (period === 'all') periodText = 'all codes';
        
        const modal = doc.getElementById('purgeCodesModal');
        if (modal) {
          modal.classList.add('hidden');
        }
        
        setPurgeButtonLoading(buttonId, true);
        
        try {
          const result = await nuiRet('purgeCodes', { period: period, includeActive: includeActive });
          setPurgeButtonLoading(buttonId, false);
          if (result && result.success) {
            if (result.count > 0) {
              const successMsg = period === 'all' 
                ? `Purged ${result.count} ${periodText}` 
                : `Purged ${result.count} codes from the last ${periodText}`;
              toast('Success', successMsg, 'success');
              refreshAll();
            } else {
              toast('Info', result.message || 'Purge operation started. You will be notified when it completes.', 'info');
            }
          } else {
            toast('Error', result && result.message ? result.message : 'Failed to purge codes', 'error');
          }
        } catch (error) {
          setPurgeButtonLoading(buttonId, false);
          console.error('Error purging codes:', error);
          toast('Error', 'Failed to purge codes', 'error');
        }
        
        window.pendingPurgeAction = null;
      }
      
      function handlePurge(period, buttonId) {
        showPurgeModal(period, buttonId);
      }
      
      doc.getElementById('purgeDayBtn')?.addEventListener('click', () => {
        handlePurge('day', 'purgeDayBtn');
      });
      
      doc.getElementById('purgeWeekBtn')?.addEventListener('click', () => {
        handlePurge('week', 'purgeWeekBtn');
      });
      
      doc.getElementById('purgeMonthBtn')?.addEventListener('click', () => {
        handlePurge('month', 'purgeMonthBtn');
      });
      
      doc.getElementById('purgeAllBtn')?.addEventListener('click', () => {
        handlePurge('all', 'purgeAllBtn');
      });
       
  
       const languageSelector = doc.getElementById('languageSelector');
       if (languageSelector) {
         const savedLang = localStorage.getItem('mr_locale') || 'en';
         
         function populateLanguageSelector() {
           const languages = {
             'en': 'UI_LANGUAGE_ENGLISH',
             'fr': 'UI_LANGUAGE_FRENCH',
             'es': 'UI_LANGUAGE_SPANISH',
             'de': 'UI_LANGUAGE_GERMAN',
             'it': 'UI_LANGUAGE_ITALIAN',
             'pt': 'UI_LANGUAGE_PORTUGUESE',
             'ru': 'UI_LANGUAGE_RUSSIAN',
             'ja': 'UI_LANGUAGE_JAPANESE',
             'ko': 'UI_LANGUAGE_KOREAN',
             'zh': 'UI_LANGUAGE_CHINESE',
             'ar': 'UI_LANGUAGE_ARABIC',
             'hi': 'UI_LANGUAGE_HINDI',
             'nl': 'UI_LANGUAGE_DUTCH',
             'sv': 'UI_LANGUAGE_SWEDISH',
             'no': 'UI_LANGUAGE_NORWEGIAN',
             'da': 'UI_LANGUAGE_DANISH',
             'fi': 'UI_LANGUAGE_FINNISH',
             'pl': 'UI_LANGUAGE_POLISH',
             'cs': 'UI_LANGUAGE_CZECH',
             'hu': 'UI_LANGUAGE_HUNGARIAN',
             'ro': 'UI_LANGUAGE_ROMANIAN',
             'el': 'UI_LANGUAGE_GREEK',
             'tr': 'UI_LANGUAGE_TURKISH',
             'he': 'UI_LANGUAGE_HEBREW',
             'th': 'UI_LANGUAGE_THAI',
             'vi': 'UI_LANGUAGE_VIETNAMESE'
           };
           
           languageSelector.innerHTML = '';
           Object.entries(languages).forEach(([code, key]) => {
             const option = doc.createElement('option');
             option.value = code;
             option.textContent = localeData[key] || key;
             languageSelector.appendChild(option);
           });
         }
         
         if (Object.keys(localeData).length > 0) {
           populateLanguageSelector();
         } else {
           requestAnimationFrame(() => populateLanguageSelector());
         }

         languageSelector.value = currentLocale || savedLang;

         if (savedLang && savedLang !== currentLocale) {

           loadLocale(savedLang).then(success => {
             if (success) {
               populateLanguageSelector();
               languageSelector.value = savedLang;

               applyLocale();

               if (currentRoute) {
                 showRoute(currentRoute);
               }
             } else {

               languageSelector.value = currentLocale || 'en';
             }
           }).catch(err => {
             languageSelector.value = currentLocale || 'en';
           });
         } else if (savedLang === currentLocale) {

           languageSelector.value = currentLocale || savedLang;
         }

         languageSelector.addEventListener('change', async (e) => {
           const newLocale = e.target.value;

           
           const success = await loadLocale(newLocale);
           if (success) {
             toast('Language Changed', `${newLocale.toUpperCase()} language applied successfully`, 'success');
           } else {
             toast('Language Error', 'Failed to change language', 'error');

             e.target.value = currentLocale;
           }
         });
       }
  
  
      const colorThemeBtns = doc.querySelectorAll('.color-theme-btn');
      colorThemeBtns.forEach(btn => {
        btn.addEventListener('click', () => {
          const theme = btn.dataset.theme;
  
          colorThemeBtns.forEach(b => b.classList.remove('active'));
  
          btn.classList.add('active');
          
          if (theme !== 'default') {
            const customColors = JSON.parse(localStorage.getItem('mr_custom_colors') || '{}');
            const root = document.documentElement;
            
            Object.keys(customColors).forEach(colorType => {
              root.style.removeProperty(`--${colorType}-custom`);
              const mainVar = colorType.replace('-custom', '');
              if (mainVar !== colorType) {
                root.style.removeProperty(`--${mainVar}`);
              }
            });
            
            localStorage.removeItem('mr_custom_colors');
          }
  
          applyColorTheme(theme);
        });
      });
      
  
      const savedTheme = localStorage.getItem('midnight_redeem_theme');
      if (savedTheme) {
  
        const savedThemeBtn = doc.querySelector(`[data-theme="${savedTheme}"]`);
        if (savedThemeBtn) {
          savedThemeBtn.classList.add('active');
          applyColorTheme(savedTheme);
        }
      } else {
  
        const defaultThemeBtn = doc.querySelector(`[data-theme="default"]`);
        if (defaultThemeBtn) {
          defaultThemeBtn.classList.add('active');
          applyColorTheme('default');
        }
      }
  
  
      
      
  
      doc.addEventListener('click', (e) => {
        const activityRow = e.target.closest('.activity-row');
        if (activityRow) {
          const codeValue = activityRow.querySelector('.code-value')?.textContent;
          if (codeValue) {
  
            showRoute('code-view');
            loadCodeDetails(codeValue);
          }
        }
      });
  
  
      doc.getElementById('backToCodes')?.addEventListener('click', () => {
        showRoute('admin-codes');
        window.currentCodeData = null;
        refreshAll();
      });
      
      doc.getElementById('editCodeBtn')?.addEventListener('click', () => {
  
        const code = doc.getElementById('viewCode')?.textContent;
        if (code) {
          showRoute('code-edit');
          editCode(code);
        }
      });
      
      doc.getElementById('copyCodeBtn')?.addEventListener('click', () => {
        const code = doc.getElementById('viewCode')?.textContent;
        if (code) {
          navigator.clipboard.writeText(code).then(() => {
            toast('Copied!', 'Code copied to clipboard', 'success');
          }).catch(() => {
            toast('Error', 'Failed to copy code', 'error');
          });
        }
      });
      
      doc.getElementById('deleteCodeBtn')?.addEventListener('click', async () => {
        const code = doc.getElementById('viewCode')?.textContent;
        if (code) {
  
          if (!window.currentCodeData || window.currentCodeData.code !== code) {
            try {
              await loadCodeDetails(code);
            } catch (error) {
              console.error('Failed to load code details for delete:', error);
            }
          }
          deleteCode(code);
        }
      });
  
  
      const codeSearch = doc.getElementById('codeSearch');
      const creatorSearch = doc.getElementById('creatorSearch');
      const applyFilters = doc.getElementById('applyFilters');
      
      if (codeSearch) {
        codeSearch.addEventListener('input', () => {
          filterCodes();
        });
      }
      
      if (creatorSearch) {
        creatorSearch.addEventListener('input', () => {
          filterCodes();
        });
      }
      
      if (applyFilters) {
        applyFilters.addEventListener('click', () => {
          filterCodes();
        });
      }
      
  
      const dateFrom = doc.getElementById('dateFrom');
      const dateTo = doc.getElementById('dateTo');
      const statusFilter = doc.getElementById('statusFilter');
      const rewardTypeFilter = doc.getElementById('rewardTypeFilter');
      
      if (dateFrom) {
        dateFrom.addEventListener('change', () => {
          filterCodes();
        });
      }
      
      if (dateTo) {
        dateTo.addEventListener('change', () => {
          filterCodes();
        });
      }
      
      if (statusFilter) {
        statusFilter.addEventListener('change', () => {
          filterCodes();
        });
      }
      
      if (rewardTypeFilter) {
        rewardTypeFilter.addEventListener('change', () => {
          filterCodes();
        });
      }

      const sortOrder = doc.getElementById('sortOrder');
      if (sortOrder) {
        sortOrder.addEventListener('change', () => {
          filterCodes();
        });
      }
  
  
      doc.getElementById('clearCodeSearch')?.addEventListener('click', () => {
        if (codeSearch) codeSearch.value = '';
        filterCodes();
      });
  
      doc.getElementById('clearCreatorSearch')?.addEventListener('click', () => {
        if (creatorSearch) creatorSearch.value = '';
        filterCodes();
      });
  
  
      const clearFilters = doc.getElementById('clearFilters');
      if (clearFilters) {
        clearFilters.addEventListener('click', () => {
  
          if (codeSearch) codeSearch.value = '';
          if (creatorSearch) creatorSearch.value = '';
          if (dateFrom) dateFrom.value = '';
          if (dateTo) dateTo.value = '';
          if (statusFilter) statusFilter.value = '';
          if (rewardTypeFilter) rewardTypeFilter.value = '';
          filterCodes();
        });
      }
  
  
      doc.getElementById('refreshCodes')?.addEventListener('click', async () => {
        // Clear all filter inputs
        const codeSearch = doc.getElementById('codeSearch');
        const creatorSearch = doc.getElementById('creatorSearch');
        const dateFrom = doc.getElementById('dateFrom');
        const dateTo = doc.getElementById('dateTo');
        const statusFilter = doc.getElementById('statusFilter');
        const rewardTypeFilter = doc.getElementById('rewardTypeFilter');
        const sortOrder = doc.getElementById('sortOrder');
        
        if (codeSearch) codeSearch.value = '';
        if (creatorSearch) creatorSearch.value = '';
        if (dateFrom) dateFrom.value = '';
        if (dateTo) dateTo.value = '';
        if (statusFilter) statusFilter.value = '';
        if (rewardTypeFilter) rewardTypeFilter.value = '';
        if (sortOrder) sortOrder.value = 'newest';
        
        // Reload codes from server
        await loadAllCodes();
        
        // Apply filters (which will show all codes since filters are cleared)
        filterCodes();
        
        toast('Refresh', 'Codes refreshed successfully', 'success');
      });
  
  
      doc.getElementById('rewardCategorySelect')?.addEventListener('change', populateCategoryRewards);
  
  
      doc.getElementById('addEditReward')?.addEventListener('click', addEditReward);
  
  
      doc.querySelectorAll('.update-permission-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const userId = btn.dataset.userId;
          const newRole = btn.dataset.role;
          updateUserPermission(userId, newRole);
        });
      });
  
      doc.querySelectorAll('.delete-user-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const userId = btn.dataset.userId;
          showDeleteUserModal(userId);
        });
      });
  
  
      window.updateUserPermission = function(userId, newRole) {
        // userId can be either a playerId (number) or identifier (string)
        // The server callback will handle both cases
        nuiRet('updateUserPermission', { identifier: userId, newRole: newRole }).then(result => {
          if (result && result.success === true) {
            toast('Success', 'User permission updated successfully', 'success');
            loadUserList();
          } else {
            const errorMsg = result && result.message ? result.message : 'Failed to update user permission';
            toast('Error', errorMsg, 'error');
          }
        }).catch(error => {
          console.error('Failed to update user permission:', error);
          toast('Error', 'Failed to update user permission', 'error');
        });
      };
  
  
      window.showDeleteUserModal = function(userId) {

        const user = window.allUsers?.find(u => u.identifier === userId);
        if (user) {
          doc.getElementById('deleteUserText').textContent = user.name || 'Unknown';
          doc.getElementById('deleteUserName').textContent = user.name || 'Unknown';
          doc.getElementById('deleteUserIdentifier').textContent = user.identifier || 'Unknown';
          doc.getElementById('deleteUserRole').textContent = user.role || 'Unknown';
        } else {
          doc.getElementById('deleteUserText').textContent = 'Unknown';
          doc.getElementById('deleteUserName').textContent = 'Unknown';
          doc.getElementById('deleteUserIdentifier').textContent = userId;
          doc.getElementById('deleteUserRole').textContent = 'Unknown';
        }
        doc.getElementById('deleteUserModal').classList.remove('hidden');
      };
  
  
      doc.getElementById('confirmDeleteCode')?.addEventListener('click', deleteSelectedCode);
      doc.getElementById('cancelDeleteCode')?.addEventListener('click', () => {
        doc.getElementById('deleteCodeModal').classList.add('hidden');
      });

      doc.getElementById('deleteUserModalClose')?.addEventListener('click', () => {
        doc.getElementById('deleteUserModal').classList.add('hidden');
      });
      
      doc.getElementById('deleteUserCancel')?.addEventListener('click', () => {
        doc.getElementById('deleteUserModal').classList.add('hidden');
      });
      
      doc.getElementById('deleteUserConfirm')?.addEventListener('click', () => {
        const userId = doc.getElementById('deleteUserIdentifier').textContent;
        const userName = doc.getElementById('deleteUserName').textContent;
        if (userId && userName) {
          deleteUser(userId, userName);
          doc.getElementById('deleteUserModal').classList.add('hidden');
        }
      });
  
  
      window.deleteSelectedCode = function() {
        const code = doc.getElementById('deleteCodeId').textContent;
        if (code) {
          nui('deleteCode', { code }).then(() => {
            toast('Success', 'Code deleted successfully', 'success');
            doc.getElementById('deleteCodeModal').classList.add('hidden');
            refreshAll();
          }).catch(error => {
            console.error('Failed to delete code:', error);
            toast('Error', 'Failed to delete code', 'error');
          });
        }
      };
  
  
      doc.getElementById('generatePreviewCode')?.addEventListener('click', generatePreviewCode);
      
  
      initRedeemUI();
    });
  
    function generatePreviewCode() {
      const code = doc.getElementById('wizardCustomCode')?.value?.trim();
      if (code) {
        doc.getElementById('previewCode').textContent = code;
        doc.getElementById('previewModal').classList.remove('hidden');
      } else {
        toast('Error', 'Please enter a code first', 'error');
      }
    }
  
  
      window.quickGenerateCode = quickGenerateCode;
      window.useSavedTemplate = useSavedTemplate;
      window.selectTemplate = selectTemplate;
      window.showSettingsSection = showSettingsSection;
      window.copyCode = copyCode;
      window.copyEditCode = copyEditCode;
  
      window.filterCodes = filterCodes;
      window.loadSavedTemplates = loadSavedTemplates;
      window.deleteSavedTemplate = deleteSavedTemplate;
      window.loadAIChatSessions = loadAIChatSessions;
  
  
      function resetSettingsPage() {
        // Close any open transcript modals
        const transcriptModal = doc.getElementById('transcriptViewerModal');
        if (transcriptModal) transcriptModal.classList.add('hidden');
        
        // Reset to default display settings section
        showSettingsSection('displaySettingsSection');
        
        // Reset color tabs to default "brand" tab
        const tabButtons = doc.querySelectorAll('.color-tab-btn');
        const tabContents = doc.querySelectorAll('.color-tab-content');
        tabButtons.forEach(btn => btn.classList.remove('active'));
        tabContents.forEach(content => content.classList.remove('active'));
        const brandTabBtn = doc.querySelector('.color-tab-btn[data-tab="brand"]');
        const brandTabContent = doc.getElementById('brand-colors');
        if (brandTabBtn) brandTabBtn.classList.add('active');
        if (brandTabContent) brandTabContent.classList.add('active');
        
        // Reset AI Chat Settings subsections
        const allSubsections = doc.querySelectorAll('.ai-chat-subsection');
        allSubsections.forEach(sub => sub.classList.add('hidden'));
        const transcriptsSection = doc.getElementById('transcriptsSection');
        if (transcriptsSection) transcriptsSection.classList.remove('hidden');
        const allSubButtons = doc.querySelectorAll('.ai-chat-settings-nav .btn');
        allSubButtons.forEach(btn => {
          btn.classList.remove('btn-primary');
          btn.classList.add('btn-secondary');
        });
        const transcriptsBtn = doc.getElementById('transcriptsBtn');
        if (transcriptsBtn) {
          transcriptsBtn.classList.remove('btn-secondary');
          transcriptsBtn.classList.add('btn-primary');
        }
        
        // Scroll to top of settings section
        const settingsRoute = doc.getElementById('route-admin-settings');
        if (settingsRoute) {
          settingsRoute.scrollTop = 0;
        }
      }

      async function loadAIChatSessions() {
        if (!aiEnabled) {
          return;
        }
        const transcriptsList = doc.getElementById('transcriptsList');
        const transcriptsLoading = doc.getElementById('transcriptsLoading');
        const transcriptsEmpty = doc.getElementById('transcriptsEmpty');
        
        if (!transcriptsList) return;
        
        // Hide empty state, show loading
        if (transcriptsLoading) transcriptsLoading.classList.remove('hidden');
        if (transcriptsEmpty) transcriptsEmpty.classList.add('hidden');
        
        // Clear existing session cards but keep loading/empty state divs
        const existingCards = transcriptsList.querySelectorAll('.transcript-card');
        existingCards.forEach(card => card.remove());
        
        try {
          // Check if user has admin permission to view all sessions
          const allSessionsResult = await nuiRet('getAllAIChatSessions', {});
          const sessionsResult = await nuiRet('getAIChatSessions', {});

          let sessions = [];
          if (sessionsResult?.success && Array.isArray(sessionsResult.sessions)) {
            sessions = sessionsResult.sessions;
          }
          if (allSessionsResult?.success && Array.isArray(allSessionsResult.sessions) && allSessionsResult.sessions.length > 0) {
            sessions = allSessionsResult.sessions;
          } else if (allSessionsResult?.success && Array.isArray(allSessionsResult.sessions) && sessions.length === 0) {
            sessions = allSessionsResult.sessions;
          }
          
          // Store all sessions for filtering
          window.allTranscripts = sessions || [];
          
          // Hide loading
          if (transcriptsLoading) transcriptsLoading.classList.add('hidden');
          
          // Apply filters and display (this will handle empty array case)
          filterTranscripts();
        } catch (error) {
          console.error('Failed to load AI chat sessions:', error);
          if (transcriptsLoading) transcriptsLoading.classList.add('hidden');
          if (transcriptsEmpty) transcriptsEmpty.classList.remove('hidden');
        }
      }
      
      function displayTranscriptResults(sessions) {
        const transcriptsList = doc.getElementById('transcriptsList');
        const transcriptsEmpty = doc.getElementById('transcriptsEmpty');
        const transcriptResultsCount = doc.getElementById('transcriptResultsCount');
        
        if (!transcriptsList) return;
        
        // Clear existing cards
        const existingCards = transcriptsList.querySelectorAll('.transcript-card');
        existingCards.forEach(card => card.remove());
        
        // Update count
        if (transcriptResultsCount) {
          const count = sessions.length;
          transcriptResultsCount.textContent = `${count} ${count === 1 ? 'transcript' : 'transcripts'} found`;
        }
        
        if (!sessions || sessions.length === 0) {
          if (transcriptsEmpty) transcriptsEmpty.classList.remove('hidden');
          return;
        }
        
        // Hide empty state since we have sessions
        if (transcriptsEmpty) transcriptsEmpty.classList.add('hidden');
        
        sessions.forEach(session => {
          const sessionCard = doc.createElement('div');
          sessionCard.className = 'transcript-card';
          sessionCard.onclick = () => viewTranscript(session);
          
          const sessionDate = new Date(session.created_at || session.updated_at);
          const dateStr = sessionDate.toLocaleString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
          });
          
          sessionCard.innerHTML = `
            <div class="transcript-card-header">
              <div class="transcript-card-id">Session ID: ${escapeHtml(session.session_id)}</div>
              <div class="transcript-card-date">${escapeHtml(dateStr)}</div>
            </div>
            <div class="transcript-card-body">
              <div class="transcript-card-info">
                <span><strong>Player:</strong> ${escapeHtml(session.player_name || 'Unknown')}</span>
                <span><strong>Messages:</strong> ${escapeHtml(session.message_count || 0)}</span>
              </div>
            </div>
          `;
          
          transcriptsList.appendChild(sessionCard);
        });
      }
      
      function filterTranscripts() {
        if (!window.allTranscripts || !Array.isArray(window.allTranscripts)) {
          window.allTranscripts = [];
        }
        
        const sessionIdSearch = doc.getElementById('transcriptSessionIdSearch')?.value.toLowerCase() || '';
        const playerSearch = doc.getElementById('transcriptPlayerSearch')?.value.toLowerCase() || '';
        const dateFrom = doc.getElementById('transcriptDateFrom')?.value || '';
        const dateTo = doc.getElementById('transcriptDateTo')?.value || '';
        const sortOrder = doc.getElementById('transcriptSortOrder')?.value || 'newest';
        
        const filteredTranscripts = window.allTranscripts.filter(session => {
          // Filter by Session ID
          if (sessionIdSearch && !session.session_id.toLowerCase().includes(sessionIdSearch)) {
            return false;
          }
          
          // Filter by Player Name
          if (playerSearch && !(session.player_name || '').toLowerCase().includes(playerSearch)) {
            return false;
          }
          
          // Filter by Date Range
          if (dateFrom || dateTo) {
            const sessionDate = new Date(session.created_at || session.updated_at);
            if (dateFrom && sessionDate < new Date(dateFrom)) {
              return false;
            }
            if (dateTo) {
              // Include the entire day for dateTo
              const dateToEnd = new Date(dateTo);
              dateToEnd.setHours(23, 59, 59, 999);
              if (sessionDate > dateToEnd) {
                return false;
              }
            }
          }
          
          return true;
        });
        
        // Sort transcripts
        const sortedTranscripts = filteredTranscripts.sort((a, b) => {
          switch (sortOrder) {
            case 'oldest':
              return new Date(a.created_at || a.updated_at) - new Date(b.created_at || b.updated_at);
            case 'player':
              const playerA = (a.player_name || '').toLowerCase();
              const playerB = (b.player_name || '').toLowerCase();
              return playerA.localeCompare(playerB);
            case 'messages':
              return (b.message_count || 0) - (a.message_count || 0);
            case 'newest':
            default:
              return new Date(b.created_at || b.updated_at) - new Date(a.created_at || a.updated_at);
          }
        });
        
        displayTranscriptResults(sortedTranscripts);
      }
      
      async function viewTranscript(session) {
        const modal = doc.getElementById('transcriptViewerModal');
        const transcriptMessages = doc.getElementById('transcriptMessages');
        const transcriptSessionId = doc.getElementById('transcriptSessionId');
        const transcriptSessionIdValue = doc.getElementById('transcriptSessionIdValue');
        const transcriptPlayerName = doc.getElementById('transcriptPlayerName');
        const transcriptCreatedAt = doc.getElementById('transcriptCreatedAt');
        const transcriptMessageCount = doc.getElementById('transcriptMessageCount');
        const transcriptDeleteBtn = doc.getElementById('transcriptDeleteBtn');
        
        if (!modal) return;
        
        // Store current session for deletion
        window.currentTranscriptSession = session;
        
        // Check permissions and show/hide delete button
        if (transcriptDeleteBtn) {
          const hasPermission = window.userPermissions && (
            window.userPermissions.level >= 2 || 
            window.userPermissions.role === 'manager' || 
            window.userPermissions.role === 'owner'
          );
          if (hasPermission) {
            transcriptDeleteBtn.classList.remove('hidden');
          } else {
            transcriptDeleteBtn.classList.add('hidden');
          }
        }
        
        // Set session info
        if (transcriptSessionId) transcriptSessionId.textContent = session.session_id;
        if (transcriptSessionIdValue) transcriptSessionIdValue.textContent = session.session_id;
        if (transcriptPlayerName) transcriptPlayerName.textContent = session.player_name || 'Unknown';
        if (transcriptCreatedAt) {
          const date = new Date(session.created_at);
          transcriptCreatedAt.textContent = date.toLocaleString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
          });
        }
        if (transcriptMessageCount) transcriptMessageCount.textContent = session.message_count || 0;
        
        // Clear and show loading
        if (transcriptMessages) {
          transcriptMessages.innerHTML = '<div class="loading-state"><i class="fas fa-spinner fa-spin"></i> Loading messages...</div>';
        }
        
        modal.classList.remove('hidden');
        
        try {
          const result = await nuiRet('getAIChatMessages', { sessionId: session.session_id });
          
          if (result && result.success && result.messages && transcriptMessages) {
            transcriptMessages.innerHTML = '';
            
            result.messages.forEach(msg => {
              const messageDiv = doc.createElement('div');
              messageDiv.className = `ai-message ${msg.role === 'user' ? 'ai-user-message' : 'ai-assistant-message'}`;
              
              const avatarDiv = doc.createElement('div');
              avatarDiv.className = 'ai-message-avatar';
              avatarDiv.innerHTML = `<i class="fas ${msg.role === 'user' ? 'fa-user' : 'fa-robot'}"></i>`;
              
              const contentDiv = doc.createElement('div');
              contentDiv.className = 'ai-message-content';
              
              // Add timestamp
              if (msg.timestamp) {
                const timestampDiv = doc.createElement('div');
                timestampDiv.className = 'ai-message-timestamp';
                const date = new Date(msg.timestamp);
                timestampDiv.textContent = date.toLocaleString('en-US', {
                  year: 'numeric',
                  month: '2-digit',
                  day: '2-digit',
                  hour: '2-digit',
                  minute: '2-digit',
                  second: '2-digit',
                  hour12: false
                }).replace(',', '');
                contentDiv.appendChild(timestampDiv);
              }
              
              // Add name tag for AI messages
              if (msg.role === 'assistant') {
                const nameTag = doc.createElement('div');
                nameTag.className = 'ai-message-name';
                nameTag.textContent = 'shadow';
                contentDiv.appendChild(nameTag);
              }
              
              const textDiv = doc.createElement('div');
              textDiv.className = 'ai-message-text';
              textDiv.textContent = msg.content || '';
              contentDiv.appendChild(textDiv);
              
              messageDiv.appendChild(avatarDiv);
              messageDiv.appendChild(contentDiv);
              transcriptMessages.appendChild(messageDiv);
            });
            
            // Scroll to bottom
            transcriptMessages.scrollTop = transcriptMessages.scrollHeight;
          } else {
            if (transcriptMessages) {
              transcriptMessages.innerHTML = '<div class="empty-state"><p>Failed to load messages</p></div>';
            }
          }
        } catch (error) {
          console.error('Failed to load transcript messages:', error);
          if (transcriptMessages) {
            transcriptMessages.innerHTML = '<div class="empty-state"><p>Error loading messages</p></div>';
          }
        }
      }
      
      // Transcript modal close handlers
      doc.getElementById('transcriptViewerModalClose')?.addEventListener('click', () => {
        doc.getElementById('transcriptViewerModal')?.classList.add('hidden');
      });
      
      doc.getElementById('transcriptViewerClose')?.addEventListener('click', () => {
        doc.getElementById('transcriptViewerModal')?.classList.add('hidden');
      });
      
      // Transcript delete button handler
      doc.getElementById('transcriptDeleteBtn')?.addEventListener('click', () => {
        if (window.currentTranscriptSession) {
          showDeleteTranscriptModal(window.currentTranscriptSession);
        }
      });
      
      // Delete transcript modal handlers
      doc.getElementById('deleteTranscriptModalClose')?.addEventListener('click', () => {
        const modal = doc.getElementById('deleteTranscriptModal');
        if (modal) modal.classList.add('hidden');
      });
      
      doc.getElementById('deleteTranscriptCancel')?.addEventListener('click', () => {
        const modal = doc.getElementById('deleteTranscriptModal');
        if (modal) modal.classList.add('hidden');
      });
      
      doc.getElementById('deleteTranscriptConfirm')?.addEventListener('click', confirmDeleteTranscript);

      function showSettingsSection(section) {
        if (section === 'aiChatSettingsSection' && !aiEnabled && !isOwnerUser) {
          section = 'displaySettingsSection';
        }

        if (section === 'runtimeConfigSection' && !isOwnerUser) {
          section = 'displaySettingsSection';
        }
  
        
  
        const allSettingsContent = doc.querySelectorAll('.settings-content');
        allSettingsContent.forEach(content => {
          content.classList.add('hidden');
        });
        
  
        const targetSection = doc.getElementById(section);
        if (targetSection) {
          targetSection.classList.remove('hidden');
  
        } else {
          console.error('Section not found:', section);
        }
        
  
        const allButtons = doc.querySelectorAll('.settings-nav .btn');
        allButtons.forEach(btn => {
          btn.classList.remove('btn-primary');
          btn.classList.add('btn-secondary');
        });
  
  
        const activeButton = doc.querySelector(`[data-section="${section}"]`);
        if (activeButton) {
          activeButton.classList.remove('btn-secondary');
          activeButton.classList.add('btn-primary');
        }
        
        // Show default subsection for AI Chat Settings and refresh transcripts
        if (section === 'aiChatSettingsSection') {
          if (aiEnabled) {
            showAIChatSubsection('transcriptsSection');
            setTimeout(() => {
              loadAIChatSessions();
            }, 100);
          } else if (isOwnerUser) {
            showAIChatSubsection('chatSettingsSection');
          }
        }

        if (section === 'runtimeConfigSection') {
          loadRuntimeConfigTab(activeRuntimeConfigTab);
        }

        if (section === 'displaySettingsSection') {
          const languageSelector = doc.getElementById('languageSelector');
          if (languageSelector) {
            const savedLang = localStorage.getItem('mr_locale') || 'en';

            if (savedLang !== currentLocale) {
          loadLocale(savedLang).then(success => {
            if (success) {
              populateLanguageSelector();
              languageSelector.value = savedLang;
                  applyLocale();
                } else {
                  languageSelector.value = currentLocale || 'en';
                }
              });
            } else {
              languageSelector.value = currentLocale || savedLang;
            }
          }

          requestAnimationFrame(() => applyLocale());
          loadVersionInfo(false);
        }
      }

    let messageQueue = [];
    let processingBatch = false;
    
    function processBatchMessages() {
      if (processingBatch || messageQueue.length === 0) return;
      
      processingBatch = true;
      const batch = messageQueue.splice(0, 10);

      batch.forEach(d => {
        try {
        if (d.action === 'showUI') {
          root.classList.remove('hidden'); 
          root.classList.add('visible');
          const mode = d.mode || 'player';
          togglePlayerChrome(mode === 'player');
          if (mode === 'admin') {
            showRoute('admin-dashboard');
          } else {
            showRoute('player');
          }
        } else if (d.action === 'hideUI') {
          root.classList.remove('visible'); 
          root.classList.add('hidden');
          resetWizard();
          resetSettingsPage();
        } else if (d.action === 'toast') {
          toast(d.title, d.description, d.type || 'info', d.duration || 2500);
        } else if (d.action === 'dashboardData') {
          loadRecentActivity();
        } else if (d.action === 'codesData') {
          updateRecentActivity(d.data);
        } else if (d.action === 'allCodesData') {
          updateAllCodesData(d.data);
        } else if (d.action === 'weeklyStats') {
          updateWeeklyStats(d.data);
        } else if (d.action === 'dailyStats') {
          updateDailyStats(d.data);
        } else if (d.action === 'rewardsStats') {
          updateRewardsStats(d.data);
        } else if (d.action === 'allDashboardData') {

          if (d.data) {
            if (d.data.weekly) updateWeeklyStats(d.data.weekly);
            if (d.data.daily) updateDailyStats(d.data.daily);
            if (d.data.rewards) updateRewardsStats(d.data.rewards);
            if (d.data.codes) updateRecentActivity(d.data.codes);
            if (d.data.allCodes) updateAllCodesData(d.data.allCodes);
          }
        }
        } catch (err) {

          console.error('NUI message handling error:', err);
        }
      });
      
      processingBatch = false;

      if (messageQueue.length > 0) {
        requestAnimationFrame(processBatchMessages);
      }
    }

    window.addEventListener('message', (e) => {
      const d = e.data || {};

      if (d.action === 'batch' && d.messages) {
        messageQueue.push(...d.messages);
        requestAnimationFrame(processBatchMessages);
        return;
      }

      messageQueue.push(d);
      requestAnimationFrame(processBatchMessages);
    });
  
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
  
        const wizardModal = doc.getElementById('wizardModal');
        if (wizardModal && !wizardModal.classList.contains('hidden')) {
          hideWizardModal();
  
          showRoute('admin-dashboard');
          return;
        }
        
  
        const deleteModal = doc.getElementById('deleteCodeModal');
        if (deleteModal && !deleteModal.classList.contains('hidden')) {
          deleteModal.classList.add('hidden');
          return;
        }
        
        const purgeModal = doc.getElementById('purgeCodesModal');
        if (purgeModal && !purgeModal.classList.contains('hidden')) {
          purgeModal.classList.add('hidden');
          window.pendingPurgeAction = null;
          return;
        }

        const editRoleModal = doc.getElementById('editRoleModal');
        if (editRoleModal && !editRoleModal.classList.contains('hidden')) {
          hideEditRoleModal();
          return;
        }
        

        const modals = ['bulkGenerateModal', 'previewModal', 'deleteCodeModal', 'deleteUserModal', 'purgeCodesModal'];
        for (const modalId of modals) {
          const modal = doc.getElementById(modalId);
          if (modal && !modal.classList.contains('hidden')) {
            modal.classList.add('hidden');
            return;
          }
        }
        
  
        nui('close');
      }
    });
  
  
  
    function loadSavedTemplates() {
  
      fetchSavedTemplates().then(result => {
  
        if (result && result.success && result.data) {
          const templates = result.data;
          const container = doc.getElementById('savedTemplates');
          if (!container) {
            console.error('savedTemplates container not found');
            return;
          }
          
          container.innerHTML = '';
          
          if (templates.length === 0) {
            container.innerHTML = '<div class="empty-state">No saved templates found</div>';
            return;
          }
          
          templates.forEach(template => {
            const rewards = template.rewards || [];
            
  
            const rewardsArray = Array.isArray(rewards) ? rewards : [];
            
            const card = doc.createElement('div');
            card.className = 'template-card saved-template';
            const safeName = escapeHtml(template.name);
            card.innerHTML = `
              <div class="template-header">
                <span class="template-icon"><i class="fas fa-save"></i></span>
                <h3>${safeName}</h3>
              </div>
              <p class="template-description">Saved template</p>
              <div class="template-rewards">
                <strong>Rewards:</strong>
                <ul>
                  ${rewardsArray.map(reward => {
                    if (reward.item) return `<li>${escapeHtml(reward.amount || 1)}x ${escapeHtml(reward.item)}</li>`;
                    if (reward.money) return `<li>$${escapeHtml(reward.amount || 0)} ${escapeHtml(reward.option || 'cash')}</li>`;
                    if (reward.vehicle) return `<li>Vehicle: ${escapeHtml(reward.model || reward.vehicle)}</li>`;
                    return '<li>Unknown reward</li>';
                  }).join('')}
                </ul>
              </div>
              <div class="template-actions">
                <button class="btn btn-primary btn-sm use-template-btn" data-template-name="${safeName}">Use Template</button>
                <button class="btn btn-danger btn-sm delete-template-btn" data-template-name="${safeName}">Delete</button>
              </div>
            `;
            card.querySelector('.use-template-btn')?.addEventListener('click', () => useSavedTemplate(template.name));
            card.querySelector('.delete-template-btn')?.addEventListener('click', () => deleteSavedTemplate(template.name));
            container.appendChild(card);
          });
        } else {
          console.error('Failed to load saved templates:', result);
          const container = doc.getElementById('savedTemplates');
          if (container) {
            container.innerHTML = '<div class="empty-state">Failed to load saved templates</div>';
          }
        }
      }).catch(error => {
        console.error('Failed to load saved templates:', error);
        const container = doc.getElementById('savedTemplates');
        if (container) {
          container.innerHTML = '<div class="empty-state">Error loading saved templates</div>';
        }
      });
    }
  
    function deleteSavedTemplate(templateName) {
      if (confirm(`Are you sure you want to delete the template "${templateName}"?`)) {
        nui('deleteSavedTemplate', { templateName }).then(() => {
          clearTemplateCaches();
          toast('Success', 'Template deleted successfully', 'success');
          loadSavedTemplates();
        }).catch(error => {
          console.error('Failed to delete template:', error);
          toast('Error', 'Failed to delete template', 'error');
        });
      }
    }
  
  
    function selectCategoryRewards(category, name) {
      fetchPreFilledRewards().then(templates => {
        if (templates && templates.success && templates.data && templates.data[category] && templates.data[category][name]) {
          const rewards = templates.data[category][name];
          if (Array.isArray(rewards)) {
            const normalizedRewards = rewards.map(reward => {
              if (reward.vehicle && reward.amount !== undefined) {
                const normalized = { vehicle: true, model: reward.model || reward.vehicle };
                if (reward.label) normalized.label = reward.label;
                return normalized;
              }
              return reward;
            });
            if (!wizardRewards) wizardRewards = [];
            wizardRewards.push(...normalizedRewards);
            updateWizardRewardsTable();
            updateRewardsSummary();
            toast('Rewards Applied', `${name} rewards added to existing rewards`, 'success');
          } else {
            toast('Error', 'Invalid rewards data', 'error');
          }
        } else {
          toast('Error', 'Template not found', 'error');
        }
      });
    }
  
    function selectCategoryReward(category, index) {
      fetchPreFilledRewards().then(templates => {
        if (templates && templates.success && templates.data) {
          let categoryData = templates.data;
          
  
          if (categoryData.reward_categories && categoryData.reward_categories[category]) {
            categoryData = categoryData.reward_categories[category];
          } else if (categoryData[category]) {
            categoryData = categoryData[category];
          } else {
            toast('Error', 'Category not found', 'error');
            return;
          }
          
          if (categoryData.rewards && Array.isArray(categoryData.rewards) && categoryData.rewards[index]) {
            const reward = categoryData.rewards[index];
            if (reward.vehicle && reward.amount !== undefined) {
              const normalizedReward = { vehicle: true, model: reward.model || reward.vehicle };
              if (reward.label) normalizedReward.label = reward.label;
              if (!wizardRewards) wizardRewards = [];
              wizardRewards.push(normalizedReward);
            } else {
              if (!wizardRewards) wizardRewards = [];
              wizardRewards.push(reward);
            }
            updateWizardRewardsTable();
            updateRewardsSummary();
            toast('Reward Applied', `${reward.label || reward.item || reward.model || 'Reward'} added to rewards`, 'success');
          } else {
            toast('Error', 'Reward not found', 'error');
          }
        } else {
          toast('Error', 'Failed to load templates', 'error');
        }
      });
    }
  
    function showTemplatesForCategory(category, categoryData) {
  
      const templateGrid = doc.getElementById('templateGrid');
      if (!templateGrid) {
        console.error('templateGrid not found');
        return;
      }
      
      templateGrid.innerHTML = '';
      
      if (!categoryData || Object.keys(categoryData).length === 0) {
        templateGrid.innerHTML = '<div class="empty-state">No templates found in this category</div>';
        return;
      }
      
      if (category === 'quick_templates') {
  
        Object.entries(categoryData).forEach(([templateKey, template]) => {
          const rewards = template.rewards || [];
          const rewardsArray = Array.isArray(rewards) ? rewards : [];
          
          const templateCard = doc.createElement('div');
          templateCard.className = 'template-card';
          templateCard.dataset.template = templateKey;
          templateCard.innerHTML = `
            <div class="template-name">${template.name}</div>
            <div class="template-preview">
              ${rewardsArray.slice(0, 3).map(reward => {
                if (reward.item) return `<i class='fas fa-box'></i> ${reward.amount || 1}x ${reward.item}`;
                if (reward.money) return `<i class='fas fa-dollar-sign'></i> $${reward.amount || 0}`;
                if (reward.vehicle) return `<i class='fas fa-car'></i> ${reward.model || reward.vehicle}`;
                return 'Unknown reward';
              }).join('<br>')}
              ${rewardsArray.length > 3 ? `<br>+${rewardsArray.length - 3} more...` : ''}
            </div>
            <div class="template-actions">
              <button class="btn btn-xs btn-secondary use-template-btn" onclick="selectTemplate('${templateKey}')">Use Template</button>
            </div>
          `;
          templateGrid.appendChild(templateCard);
        });
      } else {
  
        if (categoryData.rewards && Array.isArray(categoryData.rewards)) {
  
          categoryData.rewards.forEach((reward, index) => {
            const templateCard = doc.createElement('div');
            templateCard.className = 'template-card';
            templateCard.dataset.category = category;
            templateCard.dataset.index = index;
            templateCard.innerHTML = `
              <div class="template-name">${reward.label || reward.item || reward.model || 'Reward'}</div>
              <div class="template-preview">
                ${reward.item ? `<i class="fas fa-box"></i> ${reward.amount || 1}x ${reward.item}` : ''}
                ${reward.money ? `<i class="fas fa-dollar-sign"></i> $${reward.amount || 0} ${reward.option || 'cash'}` : ''}
                ${reward.vehicle ? `<i class="fas fa-car"></i> ${reward.model || reward.vehicle}` : ''}
              </div>
              <div class="template-actions">
                <button class="btn btn-xs btn-secondary use-template-btn" onclick="selectCategoryReward('${category}', ${index})">Use Reward</button>
              </div>
            `;
            templateGrid.appendChild(templateCard);
          });
        } else {
          Object.entries(categoryData).forEach(([name, rewards]) => {
            const rewardsArray = Array.isArray(rewards) ? rewards : [];
            
            const templateCard = doc.createElement('div');
            templateCard.className = 'template-card';
            templateCard.dataset.category = category;
            templateCard.dataset.name = name;
            templateCard.innerHTML = `
              <div class="template-name">${name}</div>
              <div class="template-preview">
                ${rewardsArray.slice(0, 3).map(reward => {
                  if (reward.item) return `<i class='fas fa-box'></i> ${reward.amount || 1}x ${reward.item}`;
                  if (reward.money) return `<i class='fas fa-dollar-sign'></i> $${reward.amount || 0}`;
                  if (reward.vehicle) return `<i class='fas fa-car'></i> ${reward.model || reward.vehicle}`;
                  return 'Unknown reward';
                }).join('<br>')}
                ${rewardsArray.length > 3 ? `<br>+${rewardsArray.length - 3} more...` : ''}
              </div>
              <div class="template-actions">
                <button class="btn btn-xs btn-secondary use-template-btn" onclick="selectCategoryRewards('${category}', '${name}')">Use Rewards</button>
              </div>
            `;
            templateGrid.appendChild(templateCard);
          });
        }
      }
    }
  
    function useSavedTemplate(templateName) {
      fetchSavedTemplates().then(savedTemplates => {
        if (savedTemplates && savedTemplates.success && savedTemplates.data) {
          const template = savedTemplates.data.find(t => t.name === templateName);
          if (template && Array.isArray(template.rewards)) {
            wizardRewards = [...template.rewards];
            updateWizardRewardsTable();
            updateRewardsSummary();
            toast('Template Applied', `${templateName} template applied successfully`, 'success');
          } else {
            toast('Error', 'Invalid template data', 'error');
          }
        } else {
          toast('Error', 'Failed to load saved templates', 'error');
        }
      });
    }
  
    function quickGenerateCode() {
  
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      let result = '';
      for (let i = 0; i < 8; i++) {
        result += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      
  
      const wizardCustomCode = doc.getElementById('wizardCustomCode');
      if (wizardCustomCode) {
        wizardCustomCode.value = result;
        toast('Code Generated', 'Random code generated successfully', 'success');
      }
    }
  
  
    function hexToRgb(hex) {
      const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
      return result ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16)
      } : { r: 66, g: 153, b: 225 };
    }
  
  
    function applyCustomColor(colorType, colorValue) {
      const root = document.documentElement;
      
      root.style.setProperty(`--${colorType}-custom`, colorValue);
      
      const mainVar = colorType.replace('-custom', '');
      if (mainVar !== colorType) {
        root.style.setProperty(`--${mainVar}`, colorValue);
      }
      
      if (colorType === 'primary-dark-custom') {
        root.style.setProperty('--brand-primary-dark', colorValue);
        const primaryColor = getComputedStyle(root).getPropertyValue('--brand-primary').trim() || '#4299e1';
        root.style.setProperty('--primary', `linear-gradient(135deg, ${primaryColor} 0%, ${colorValue} 100%)`);
      } else if (colorType === 'success-dark-custom') {
        root.style.setProperty('--status-success-dark', colorValue);
        const successColor = getComputedStyle(root).getPropertyValue('--status-success').trim() || '#48bb78';
        root.style.setProperty('--success', `linear-gradient(135deg, ${successColor} 0%, ${colorValue} 100%)`);
      } else if (colorType === 'danger-dark-custom') {
        root.style.setProperty('--status-danger-dark', colorValue);
        const dangerColor = getComputedStyle(root).getPropertyValue('--status-danger').trim() || '#f56565';
        root.style.setProperty('--danger', `linear-gradient(135deg, ${dangerColor} 0%, ${colorValue} 100%)`);
      } else if (colorType === 'warning-dark-custom') {
        root.style.setProperty('--status-warning-dark', colorValue);
        const warningColor = getComputedStyle(root).getPropertyValue('--status-warning').trim() || '#ed8936';
        root.style.setProperty('--warning', `linear-gradient(135deg, ${warningColor} 0%, ${colorValue} 100%)`);
      } else if (colorType === 'primary-custom') {
        root.style.setProperty('--brand-primary', colorValue);
        const primaryDark = getComputedStyle(root).getPropertyValue('--brand-primary-dark').trim() || '#3182ce';
        root.style.setProperty('--primary', `linear-gradient(135deg, ${colorValue} 0%, ${primaryDark} 100%)`);
      } else if (colorType === 'success-custom') {
        root.style.setProperty('--status-success', colorValue);
        const successDark = getComputedStyle(root).getPropertyValue('--status-success-dark').trim() || '#38a169';
        root.style.setProperty('--success', `linear-gradient(135deg, ${colorValue} 0%, ${successDark} 100%)`);
      } else if (colorType === 'danger-custom') {
        root.style.setProperty('--status-danger', colorValue);
        const dangerDark = getComputedStyle(root).getPropertyValue('--status-danger-dark').trim() || '#e53e3e';
        root.style.setProperty('--danger', `linear-gradient(135deg, ${colorValue} 0%, ${dangerDark} 100%)`);
      } else if (colorType === 'warning-custom') {
        root.style.setProperty('--status-warning', colorValue);
        const warningDark = getComputedStyle(root).getPropertyValue('--status-warning-dark').trim() || '#dd6b20';
        root.style.setProperty('--warning', `linear-gradient(135deg, ${colorValue} 0%, ${warningDark} 100%)`);
      }
      
      if (colorType === 'bg-custom') {
        root.style.setProperty('--base-900', colorValue);
        const bgRgb = hexToRgb(colorValue);
        const bgLighter = `rgba(${Math.min(255, bgRgb.r + 20)}, ${Math.min(255, bgRgb.g + 20)}, ${Math.min(255, bgRgb.b + 20)}, 0.95)`;
        const bgSecondary = `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 1.0)`;
        const bgTertiary = `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 0.85)`;
        const base800 = `rgb(${Math.min(255, bgRgb.r + 10)}, ${Math.min(255, bgRgb.g + 10)}, ${Math.min(255, bgRgb.b + 10)})`;
        const base700 = `rgb(${Math.min(255, bgRgb.r + 35)}, ${Math.min(255, bgRgb.g + 35)}, ${Math.min(255, bgRgb.b + 35)})`;
        
        const customColors = JSON.parse(localStorage.getItem('mr_custom_colors') || '{}');
        const bgPrimaryHex = `#${Math.min(255, bgRgb.r + 20).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.g + 20).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.b + 20).toString(16).padStart(2, '0')}`;
        
        if (!customColors['bg-primary-custom']) {
          root.style.setProperty('--bg-primary', bgLighter);
          root.style.setProperty('--bg-primary-custom', bgPrimaryHex);
        }
        if (!customColors['bg-secondary-custom']) {
          root.style.setProperty('--bg-secondary', bgSecondary);
          root.style.setProperty('--bg-secondary-custom', colorValue);
        }
        if (!customColors['bg-tertiary-custom']) {
          root.style.setProperty('--bg-tertiary', bgTertiary);
          root.style.setProperty('--bg-tertiary-custom', colorValue);
        }
        root.style.setProperty('--base-800', base800);
        root.style.setProperty('--base-700', base700);
        root.style.setProperty('--bg', `linear-gradient(135deg, ${colorValue} 0%, ${base800} 25%, ${base700} 100%)`);
        
        const bgPrimaryPicker = document.getElementById('bg-primary-custom');
        const bgSecondaryPicker = document.getElementById('bg-secondary-custom');
        const bgTertiaryPicker = document.getElementById('bg-tertiary-custom');
        if (bgPrimaryPicker && !customColors['bg-primary-custom']) {
          bgPrimaryPicker.value = bgPrimaryHex;
        }
        if (bgSecondaryPicker && !customColors['bg-secondary-custom']) {
          bgSecondaryPicker.value = colorValue;
        }
        if (bgTertiaryPicker && !customColors['bg-tertiary-custom']) {
          bgTertiaryPicker.value = colorValue;
        }
      } else if (colorType === 'panel-custom') {
        const panelRgb = hexToRgb(colorValue);
        root.style.setProperty('--panel', `rgba(${panelRgb.r}, ${panelRgb.g}, ${panelRgb.b}, 0.8)`);
        root.style.setProperty('--panel-custom', colorValue);
      } else if (colorType === 'bg-secondary-custom') {
        const bgRgb = hexToRgb(colorValue);
        root.style.setProperty('--bg-secondary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 1.0)`);
      } else if (colorType === 'bg-primary-custom') {
        const bgRgb = hexToRgb(colorValue);
        root.style.setProperty('--bg-primary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 0.95)`);
      } else if (colorType === 'bg-tertiary-custom') {
        const bgRgb = hexToRgb(colorValue);
        root.style.setProperty('--bg-tertiary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 0.85)`);
      } else if (colorType === 'glass-custom') {
        const glassRgb = hexToRgb(colorValue);
        root.style.setProperty('--glass', `rgba(${glassRgb.r}, ${glassRgb.g}, ${glassRgb.b}, 0.05)`);
      } else if (colorType === 'input-bg-custom') {
        const inputRgb = hexToRgb(colorValue);
        root.style.setProperty('--input-bg', `rgba(${inputRgb.r}, ${inputRgb.g}, ${inputRgb.b}, 0.65)`);
        root.style.setProperty('--input-bg-custom', colorValue);
      }
      
      const customColors = JSON.parse(localStorage.getItem('mr_custom_colors') || '{}');
      customColors[colorType] = colorValue;
      localStorage.setItem('mr_custom_colors', JSON.stringify(customColors));
    }
    
    function loadCustomColors() {
      const customColors = JSON.parse(localStorage.getItem('mr_custom_colors') || '{}');
      const currentTheme = localStorage.getItem('mr_theme') || 'dark';
      const isLight = currentTheme === 'light';
      const root = document.documentElement;
      
      if (Object.keys(customColors).length === 0) {
        return;
      }
      
      const backgroundColors = ['bg-custom', 'bg-primary-custom', 'bg-secondary-custom', 'bg-tertiary-custom', 'panel-custom', 'glass-custom', 'input-bg-custom'];
      const textColors = ['text-custom', 'text-muted-custom', 'text-dim-custom', 'text-secondary-custom', 'text-tertiary-custom'];
      
      Object.entries(customColors).forEach(([colorType, colorValue]) => {
        // Don't override background colors when using light/dark theme (only when theme is 'default')
        if (currentTheme !== 'dark' && currentTheme !== 'light' && backgroundColors.includes(colorType)) {
          return;
        }
        
        // Don't override text colors when using light/dark theme - let theme handle text colors
        if ((currentTheme === 'dark' || currentTheme === 'light') && textColors.includes(colorType)) {
          return;
        }
        
        root.style.setProperty(`--${colorType}-custom`, colorValue);
        
        const mainVar = colorType.replace('-custom', '');
        if (mainVar !== colorType) {
          if (colorType === 'panel-custom') {
            const panelRgb = hexToRgb(colorValue);
            const panelOpacity = isLight ? 0.85 : 0.8;
            root.style.setProperty('--panel', `rgba(${panelRgb.r}, ${panelRgb.g}, ${panelRgb.b}, ${panelOpacity})`);
          } else if (colorType === 'bg-secondary-custom') {
            const bgRgb = hexToRgb(colorValue);
            const bgOpacity = isLight ? 1.0 : 1.0;
            root.style.setProperty('--bg-secondary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, ${bgOpacity})`);
          } else if (colorType === 'bg-primary-custom') {
            const bgRgb = hexToRgb(colorValue);
            const bgOpacity = isLight ? 0.95 : 0.95;
            root.style.setProperty('--bg-primary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, ${bgOpacity})`);
        } else if (colorType === 'bg-tertiary-custom') {
          const bgRgb = hexToRgb(colorValue);
          const bgOpacity = isLight ? 0.85 : 0.85;
          root.style.setProperty('--bg-tertiary', `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, ${bgOpacity})`);
        } else if (colorType === 'glass-custom') {
          const glassRgb = hexToRgb(colorValue);
          const glassOpacity = isLight ? 0.8 : 0.05;
          root.style.setProperty('--glass', `rgba(${glassRgb.r}, ${glassRgb.g}, ${glassRgb.b}, ${glassOpacity})`);
        } else if (colorType === 'input-bg-custom') {
          const inputRgb = hexToRgb(colorValue);
          const inputOpacity = isLight ? 0.8 : 0.65;
          root.style.setProperty('--input-bg', `rgba(${inputRgb.r}, ${inputRgb.g}, ${inputRgb.b}, ${inputOpacity})`);
          root.style.setProperty('--input-bg-custom', colorValue);
        } else if (colorType === 'primary-dark-custom') {
          root.style.setProperty('--brand-primary-dark', colorValue);
          root.style.setProperty('--primary-dark', colorValue);
          const primaryColor = getComputedStyle(root).getPropertyValue('--brand-primary').trim() || '#4299e1';
          root.style.setProperty('--primary', `linear-gradient(135deg, ${primaryColor} 0%, ${colorValue} 100%)`);
        } else if (colorType === 'success-dark-custom') {
          root.style.setProperty('--status-success-dark', colorValue);
          root.style.setProperty('--success-dark', colorValue);
          const successColor = getComputedStyle(root).getPropertyValue('--status-success').trim() || '#48bb78';
          root.style.setProperty('--success', `linear-gradient(135deg, ${successColor} 0%, ${colorValue} 100%)`);
        } else if (colorType === 'danger-dark-custom') {
          root.style.setProperty('--status-danger-dark', colorValue);
          root.style.setProperty('--danger-dark', colorValue);
          const dangerColor = getComputedStyle(root).getPropertyValue('--status-danger').trim() || '#f56565';
          root.style.setProperty('--danger', `linear-gradient(135deg, ${dangerColor} 0%, ${colorValue} 100%)`);
        } else if (colorType === 'warning-dark-custom') {
          root.style.setProperty('--status-warning-dark', colorValue);
          root.style.setProperty('--warning-dark', colorValue);
          const warningColor = getComputedStyle(root).getPropertyValue('--status-warning').trim() || '#ed8936';
          root.style.setProperty('--warning', `linear-gradient(135deg, ${warningColor} 0%, ${colorValue} 100%)`);
        } else if (colorType === 'primary-custom') {
          root.style.setProperty('--brand-primary', colorValue);
          const primaryDark = getComputedStyle(root).getPropertyValue('--brand-primary-dark').trim() || '#3182ce';
          root.style.setProperty('--primary', `linear-gradient(135deg, ${colorValue} 0%, ${primaryDark} 100%)`);
        } else if (colorType === 'success-custom') {
          root.style.setProperty('--status-success', colorValue);
          const successDark = getComputedStyle(root).getPropertyValue('--status-success-dark').trim() || '#38a169';
          root.style.setProperty('--success', `linear-gradient(135deg, ${colorValue} 0%, ${successDark} 100%)`);
        } else if (colorType === 'danger-custom') {
          root.style.setProperty('--status-danger', colorValue);
          const dangerDark = getComputedStyle(root).getPropertyValue('--status-danger-dark').trim() || '#e53e3e';
          root.style.setProperty('--danger', `linear-gradient(135deg, ${colorValue} 0%, ${dangerDark} 100%)`);
        } else if (colorType === 'warning-custom') {
          root.style.setProperty('--status-warning', colorValue);
          const warningDark = getComputedStyle(root).getPropertyValue('--status-warning-dark').trim() || '#dd6b20';
          root.style.setProperty('--warning', `linear-gradient(135deg, ${colorValue} 0%, ${warningDark} 100%)`);
          } else if (!textColors.includes(colorType)) {
            // Don't override text variables when using light/dark theme
            root.style.setProperty(`--${mainVar}`, colorValue);
          }
        }
      });
      
      if (customColors['bg-custom'] && currentTheme !== 'dark' && currentTheme !== 'light') {
        const bgRgb = hexToRgb(customColors['bg-custom']);
        const base800 = `rgb(${Math.min(255, bgRgb.r + 10)}, ${Math.min(255, bgRgb.g + 10)}, ${Math.min(255, bgRgb.b + 10)})`;
        const base700 = `rgb(${Math.min(255, bgRgb.r + 35)}, ${Math.min(255, bgRgb.g + 35)}, ${Math.min(255, bgRgb.b + 35)})`;
        root.style.setProperty('--base-900', customColors['bg-custom']);
        root.style.setProperty('--base-800', base800);
        root.style.setProperty('--base-700', base700);
        root.style.setProperty('--bg', `linear-gradient(135deg, ${customColors['bg-custom']} 0%, ${base800} 25%, ${base700} 100%)`);
      }
    }
    
    function resetCustomColors() {
      localStorage.removeItem('mr_custom_colors');
      
      const currentTheme = localStorage.getItem('midnight_redeem_theme') || 'default';
      
      clearAllCustomVariables();
      
      applyColorTheme(currentTheme);
      
      updateColorPickerValues();
      
      toast('Colors Reset', 'All custom colors have been reset to theme defaults', 'success');
    }
    
    function clearAllCustomVariables() {
      const root = document.documentElement;
      
  
      const allCustomVars = [
        'primary-custom', 'primary-dark-custom',
        'success-custom', 'success-dark-custom', 'danger-custom', 'danger-dark-custom', 
        'warning-custom', 'warning-dark-custom',
        'bg-custom', 'bg-primary-custom', 'bg-secondary-custom', 'bg-tertiary-custom',
        'panel-custom', 'glass-custom',
        'text-custom', 'text-muted-custom', 'text-dim-custom', 'text-secondary-custom', 
        'text-tertiary-custom',
        'border-custom', 'glass-border-custom', 'panel-border-custom',
        'hover-bg-custom', 'active-bg-custom', 'input-bg-custom',
        'shadow-custom', 'shadow-lg-custom', 'shadow-xl-custom',
        'primary-glow-custom', 'accent-glow-custom', 'success-glow-custom', 
        'danger-glow-custom', 'warning-glow-custom'
      ];
      
      allCustomVars.forEach(varName => {
        root.style.removeProperty(`--${varName}`);
      });
      
      const mainVars = [
        'bg-primary', 'bg-secondary', 'bg-tertiary', 'panel', 'glass',
        'text', 'text-muted', 'text-dim', 'text-secondary', 'text-tertiary',
        'border', 'glass-border', 'panel-border', 'hover-bg', 'active-bg', 'input-bg',
        'shadow', 'shadow-lg', 'shadow-xl', 'primary-glow', 'accent-glow',
        'success-glow', 'danger-glow', 'warning-glow'
      ];
      
      mainVars.forEach(varName => {
        root.style.removeProperty(`--${varName}`);
      });
    }
    
  
    
    function updateColorPickerValues() {
      const colorPickers = document.querySelectorAll('.color-picker');
      colorPickers.forEach(picker => {
        const colorType = picker.id;
        const root = document.documentElement;
        const computedStyle = getComputedStyle(root);
        
        const cssVar = `--${colorType}`;
        const currentValue = computedStyle.getPropertyValue(cssVar).trim();
        
        let hexValue = currentValue;
        if (currentValue.startsWith('rgb')) {
          hexValue = rgbToHex(currentValue);
        } else if (currentValue.startsWith('var(')) {
          const resolvedValue = computedStyle.getPropertyValue(currentValue.slice(4, -1)).trim();
          if (resolvedValue.startsWith('rgb')) {
            hexValue = rgbToHex(resolvedValue);
          } else {
            hexValue = resolvedValue;
          }
        }
        
  
        if (hexValue && hexValue !== '') {
          picker.value = hexValue;
        }
      });
    }
    
    function rgbToHex(rgb) {
      const result = rgb.match(/\d+/g);
      if (result && result.length >= 3) {
        const r = parseInt(result[0]);
        const g = parseInt(result[1]);
        const b = parseInt(result[2]);
        return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
      }
      return rgb;
    }
    
    function saveCustomColors() {
      toast('Colors Saved', 'Your custom colors have been saved', 'success');
    }
    
    function initColorCustomization() {
      const tabButtons = document.querySelectorAll('.color-tab-btn');
      const tabContents = document.querySelectorAll('.color-tab-content');
      
      tabButtons.forEach(button => {
        button.addEventListener('click', () => {
          const targetTab = button.dataset.tab;
          
          tabButtons.forEach(btn => btn.classList.remove('active'));
          tabContents.forEach(content => content.classList.remove('active'));
          
          button.classList.add('active');
          const targetContent = document.getElementById(`${targetTab}-colors`);
          if (targetContent) {
            targetContent.classList.add('active');
          }
        });
      });
      
      const colorPickers = document.querySelectorAll('.color-picker');
      colorPickers.forEach(picker => {
        const colorType = picker.id;
        const savedColors = JSON.parse(localStorage.getItem('mr_custom_colors') || '{}');
        if (savedColors[colorType]) {
          picker.value = savedColors[colorType];
        } else {
          const root = document.documentElement;
          const computedStyle = getComputedStyle(root);
          
          let cssVar = `--${colorType}`;
          let currentValue = computedStyle.getPropertyValue(cssVar).trim();
          
          if (!currentValue || currentValue === '') {
            const mainVar = colorType.replace('-custom', '');
            cssVar = `--${mainVar}`;
            currentValue = computedStyle.getPropertyValue(cssVar).trim();
          }
          
          if (currentValue && currentValue !== '') {
            let hexValue = currentValue;
            if (currentValue.startsWith('rgb')) {
              hexValue = rgbToHex(currentValue);
            } else if (currentValue.startsWith('var(')) {
              const varName = currentValue.slice(4, -1).trim();
              const resolvedValue = computedStyle.getPropertyValue(varName).trim();
              if (resolvedValue.startsWith('rgb')) {
                hexValue = rgbToHex(resolvedValue);
              } else if (resolvedValue && !resolvedValue.startsWith('var(')) {
                hexValue = resolvedValue;
              }
            }
            
            if (hexValue && hexValue !== '' && hexValue.length <= 7) {
              picker.value = hexValue;
            }
          }
        }
        
        picker.addEventListener('change', (e) => {
          const colorType = e.target.id;
          const colorValue = e.target.value;
          applyCustomColor(colorType, colorValue);
        });
        
        picker.addEventListener('input', (e) => {
          const colorType = e.target.id;
          const colorValue = e.target.value;
          applyCustomColor(colorType, colorValue);
        });
      });
    }
  
    function applyColorTheme(theme) {
      const root = document.documentElement;
      
      const themes = {
        default: {
          primary: '#4299e1',
          primaryDark: '#3182ce',
          accent: '#9f7aea',
          accentDark: '#805ad5',
          success: '#48bb78',
          successDark: '#38a169',
          danger: '#f56565',
          dangerDark: '#e53e3e',
          warning: '#ed8936',
          warningDark: '#dd6b20',
          bg: '#0a0e1a'
        },
        blue: {
          primary: '#3b82f6',
          primaryDark: '#1d4ed8',
          accent: '#60a5fa',
          accentDark: '#3b82f6',
          success: '#10b981',
          successDark: '#059669',
          danger: '#ef4444',
          dangerDark: '#dc2626',
          warning: '#f59e0b',
          warningDark: '#d97706',
          bg: '#0f172a'
        },
        green: {
          primary: '#10b981',
          primaryDark: '#059669',
          accent: '#34d399',
          accentDark: '#10b981',
          success: '#10b981',
          successDark: '#059669',
          danger: '#ef4444',
          dangerDark: '#dc2626',
          warning: '#f59e0b',
          warningDark: '#d97706',
          bg: '#0f172a'
        },
        purple: {
          primary: '#8b5cf6',
          primaryDark: '#7c3aed',
          accent: '#a78bfa',
          accentDark: '#8b5cf6',
          success: '#10b981',
          successDark: '#059669',
          danger: '#ef4444',
          dangerDark: '#dc2626',
          warning: '#f59e0b',
          warningDark: '#d97706',
          bg: '#1e1b4b'
        },
        red: {
          primary: '#ef4444',
          primaryDark: '#dc2626',
          accent: '#f87171',
          accentDark: '#ef4444',
          success: '#10b981',
          successDark: '#059669',
          danger: '#ef4444',
          dangerDark: '#dc2626',
          warning: '#f59e0b',
          warningDark: '#d97706',
          bg: '#450a0a'
        },
        orange: {
          primary: '#f59e0b',
          primaryDark: '#d97706',
          accent: '#fbbf24',
          accentDark: '#f59e0b',
          success: '#10b981',
          successDark: '#059669',
          danger: '#ef4444',
          dangerDark: '#dc2626',
          warning: '#f59e0b',
          warningDark: '#d97706',
          bg: '#451a03'
        }
      };
      
      const selectedTheme = themes[theme] || themes.default;
      
  
      root.style.setProperty('--primary-custom', selectedTheme.primary);
      root.style.setProperty('--primary-dark-custom', selectedTheme.primaryDark);
      
      root.style.setProperty('--success-custom', selectedTheme.success);
      root.style.setProperty('--success-dark-custom', selectedTheme.successDark);
      root.style.setProperty('--danger-custom', selectedTheme.danger);
      root.style.setProperty('--danger-dark-custom', selectedTheme.dangerDark);
      root.style.setProperty('--warning-custom', selectedTheme.warning);
      root.style.setProperty('--warning-dark-custom', selectedTheme.warningDark);
      
      const bgRgb = hexToRgb(selectedTheme.bg);
      const bgLighter = `rgba(${Math.min(255, bgRgb.r + 20)}, ${Math.min(255, bgRgb.g + 20)}, ${Math.min(255, bgRgb.b + 20)}, 0.95)`;
      const bgSecondary = `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 1.0)`;
      const bgTertiary = `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 0.85)`;
      const panelColor = `rgba(${Math.min(255, bgRgb.r + 35)}, ${Math.min(255, bgRgb.g + 35)}, ${Math.min(255, bgRgb.b + 35)}, 0.8)`;
      const primaryRgbForGlass = hexToRgb(selectedTheme.primary);
      const glassRgb = {
        r: Math.min(255, Math.floor(bgRgb.r * 0.3 + primaryRgbForGlass.r * 0.7)),
        g: Math.min(255, Math.floor(bgRgb.g * 0.3 + primaryRgbForGlass.g * 0.7)),
        b: Math.min(255, Math.floor(bgRgb.b * 0.3 + primaryRgbForGlass.b * 0.7))
      };
      const glassColor = `rgba(${glassRgb.r}, ${glassRgb.g}, ${glassRgb.b}, 0.08)`;
      const inputRgb = {
        r: Math.min(255, bgRgb.r + 55),
        g: Math.min(255, bgRgb.g + 55),
        b: Math.min(255, bgRgb.b + 55)
      };
      const inputColor = `rgba(${inputRgb.r}, ${inputRgb.g}, ${inputRgb.b}, 0.65)`;
      
      const base800 = `rgb(${Math.min(255, bgRgb.r + 10)}, ${Math.min(255, bgRgb.g + 10)}, ${Math.min(255, bgRgb.b + 10)})`;
      const base700 = `rgb(${Math.min(255, bgRgb.r + 35)}, ${Math.min(255, bgRgb.g + 35)}, ${Math.min(255, bgRgb.b + 35)})`;
      
      root.style.setProperty('--base-900', selectedTheme.bg);
      root.style.setProperty('--base-800', base800);
      root.style.setProperty('--base-700', base700);
      root.style.setProperty('--bg-custom', selectedTheme.bg);
      root.style.setProperty('--bg-primary', bgLighter);
      const bgPrimaryHex = `#${Math.min(255, bgRgb.r + 20).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.g + 20).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.b + 20).toString(16).padStart(2, '0')}`;
      root.style.setProperty('--bg-primary-custom', bgPrimaryHex);
      root.style.setProperty('--bg-secondary', bgSecondary);
      root.style.setProperty('--bg-secondary-custom', selectedTheme.bg);
      root.style.setProperty('--bg-tertiary', bgTertiary);
      const bgTertiaryHex = `#${bgRgb.r.toString(16).padStart(2, '0')}${bgRgb.g.toString(16).padStart(2, '0')}${bgRgb.b.toString(16).padStart(2, '0')}`;
      root.style.setProperty('--bg-tertiary-custom', bgTertiaryHex);
      root.style.setProperty('--panel', panelColor);
      const panelHex = `#${Math.min(255, bgRgb.r + 35).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.g + 35).toString(16).padStart(2, '0')}${Math.min(255, bgRgb.b + 35).toString(16).padStart(2, '0')}`;
      root.style.setProperty('--panel-custom', panelHex);
      root.style.setProperty('--glass', glassColor);
      const glassHex = `#${glassRgb.r.toString(16).padStart(2, '0')}${glassRgb.g.toString(16).padStart(2, '0')}${glassRgb.b.toString(16).padStart(2, '0')}`;
      root.style.setProperty('--glass-custom', glassHex);
      root.style.setProperty('--input-bg', inputColor);
      const inputHex = `#${inputRgb.r.toString(16).padStart(2, '0')}${inputRgb.g.toString(16).padStart(2, '0')}${inputRgb.b.toString(16).padStart(2, '0')}`;
      root.style.setProperty('--input-bg-custom', inputHex);
      
      root.style.setProperty('--bg', `linear-gradient(135deg, ${selectedTheme.bg} 0%, ${base800} 25%, ${base700} 100%)`);
      
      const textColor = selectedTheme.bg === '#0a0e1a' ? '#f1f5f9' : '#0f172a';
      const textMuted = selectedTheme.bg === '#0a0e1a' ? '#94a3b8' : '#64748b';
      const textDim = selectedTheme.bg === '#0a0e1a' ? '#64748b' : '#475569';
      
      root.style.setProperty('--text-custom', textColor);
      root.style.setProperty('--text-muted-custom', textMuted);
      root.style.setProperty('--text-dim-custom', textDim);
      root.style.setProperty('--text-secondary-custom', textMuted);
      root.style.setProperty('--text-tertiary-custom', textDim);
      
      const borderRgb = hexToRgb(selectedTheme.primary);
      const borderColor = `rgba(${borderRgb.r}, ${borderRgb.g}, ${borderRgb.b}, 0.15)`;
      const glassBorderColor = `rgba(${Math.min(255, bgRgb.r + 100)}, ${Math.min(255, bgRgb.g + 100)}, ${Math.min(255, bgRgb.b + 100)}, 0.1)`;
      const panelBorderColor = `rgba(${Math.min(255, bgRgb.r + 80)}, ${Math.min(255, bgRgb.g + 80)}, ${Math.min(255, bgRgb.b + 80)}, 0.1)`;
      
      root.style.setProperty('--border', borderColor);
      root.style.setProperty('--border-custom', borderColor);
      root.style.setProperty('--glass-border', glassBorderColor);
      root.style.setProperty('--glass-border-custom', glassBorderColor);
      root.style.setProperty('--panel-border', panelBorderColor);
      root.style.setProperty('--panel-border-custom', panelBorderColor);
      
      root.style.setProperty('--brand-primary', selectedTheme.primary);
      root.style.setProperty('--brand-primary-dark', selectedTheme.primaryDark);
      root.style.setProperty('--brand-accent', selectedTheme.accent);
      root.style.setProperty('--brand-accent-dark', selectedTheme.accentDark);
      
      root.style.setProperty('--status-success', selectedTheme.success);
      root.style.setProperty('--status-success-dark', selectedTheme.successDark);
      root.style.setProperty('--status-danger', selectedTheme.danger);
      root.style.setProperty('--status-danger-dark', selectedTheme.dangerDark);
      root.style.setProperty('--status-warning', selectedTheme.warning);
      root.style.setProperty('--status-warning-dark', selectedTheme.warningDark);
      
      root.style.setProperty('--primary', `linear-gradient(135deg, ${selectedTheme.primary} 0%, ${selectedTheme.primaryDark} 100%)`);
      root.style.setProperty('--accent', `linear-gradient(135deg, ${selectedTheme.accent} 0%, ${selectedTheme.accentDark} 100%)`);
      root.style.setProperty('--success', `linear-gradient(135deg, ${selectedTheme.success} 0%, ${selectedTheme.successDark} 100%)`);
      root.style.setProperty('--danger', `linear-gradient(135deg, ${selectedTheme.danger} 0%, ${selectedTheme.dangerDark} 100%)`);
      root.style.setProperty('--warning', `linear-gradient(135deg, ${selectedTheme.warning} 0%, ${selectedTheme.warningDark} 100%)`);
      
      root.style.setProperty('--primary-glow', `0 0 20px ${selectedTheme.primary}40`);
      root.style.setProperty('--accent-glow', `0 0 20px ${selectedTheme.accent}40`);
      root.style.setProperty('--success-glow', `0 0 20px ${selectedTheme.success}40`);
      root.style.setProperty('--danger-glow', `0 0 20px ${selectedTheme.danger}40`);
      root.style.setProperty('--warning-glow', `0 0 20px ${selectedTheme.warning}40`);
      
      root.style.setProperty('--hover-bg', `${selectedTheme.primary}14`);
      root.style.setProperty('--active-bg', `${selectedTheme.primary}1f`);
      
      root.style.setProperty('--primary-hover', selectedTheme.primaryDark);
      root.style.setProperty('--accent-hover', selectedTheme.accentDark);
      root.style.setProperty('--success-hover', selectedTheme.successDark);
      root.style.setProperty('--danger-hover', selectedTheme.dangerDark);
      root.style.setProperty('--warning-hover', selectedTheme.warningDark);
      
      const primaryRgb = hexToRgb(selectedTheme.primary);
      const accentRgb = hexToRgb(selectedTheme.accent);
      const successRgb = hexToRgb(selectedTheme.success);
      
      root.style.setProperty('--bg-overlay', 
        `radial-gradient(circle at 20% 50%, rgba(${primaryRgb.r}, ${primaryRgb.g}, ${primaryRgb.b}, 0.15), transparent 50%), ` +
        `radial-gradient(circle at 80% 20%, rgba(${accentRgb.r}, ${accentRgb.g}, ${accentRgb.b}, 0.1), transparent 50%), ` +
        `radial-gradient(circle at 40% 80%, rgba(${successRgb.r}, ${successRgb.g}, ${successRgb.b}, 0.08), transparent 50%)`
      );
      
      root.style.setProperty('--panel-glow', `0 0 40px rgba(${primaryRgb.r}, ${primaryRgb.g}, ${primaryRgb.b}, 0.1)`);
      
      root.style.setProperty('--sidebar-gradient', 
        `linear-gradient(180deg, rgba(${primaryRgb.r}, ${primaryRgb.g}, ${primaryRgb.b}, 0.05) 0%, rgba(${accentRgb.r}, ${accentRgb.g}, ${accentRgb.b}, 0.03) 50%, rgba(${successRgb.r}, ${successRgb.g}, ${successRgb.b}, 0.02) 100%)`
      );
      
      root.style.setProperty('--topbar-gradient', 
        `linear-gradient(90deg, rgba(${primaryRgb.r}, ${primaryRgb.g}, ${primaryRgb.b}, 0.02) 0%, rgba(${accentRgb.r}, ${accentRgb.g}, ${accentRgb.b}, 0.01) 100%)`
      );
      
      const modalBgRgb = hexToRgb(selectedTheme.bg);
      root.style.setProperty('--modal-backdrop', `rgba(${modalBgRgb.r}, ${modalBgRgb.g}, ${modalBgRgb.b}, 0.85)`);
      
      const shadowColor = `rgba(${bgRgb.r}, ${bgRgb.g}, ${bgRgb.b}, 1)`;
      const shadowColorDark = `rgba(${Math.max(0, bgRgb.r - 20)}, ${Math.max(0, bgRgb.g - 20)}, ${Math.max(0, bgRgb.b - 20)}, 1)`;
      root.style.setProperty('--app-shadow-color', shadowColor);
      root.style.setProperty('--app-shadow-color-dark', shadowColorDark);
      
      root.style.setProperty('--text-accent', selectedTheme.primary);
      localStorage.setItem('midnight_redeem_theme', theme);
      
      requestAnimationFrame(() => {
        const colorPickers = doc.querySelectorAll('.color-picker');
        colorPickers.forEach(picker => {
          const colorType = picker.id;
          const root = document.documentElement;
          const computedStyle = getComputedStyle(root);
          
          let cssVar = `--${colorType}`;
          let currentValue = computedStyle.getPropertyValue(cssVar).trim();
          
          if (!currentValue || currentValue === '') {
            const mainVar = colorType.replace('-custom', '');
            cssVar = `--${mainVar}`;
            currentValue = computedStyle.getPropertyValue(cssVar).trim();
          }
          
          if (currentValue && currentValue !== '') {
            let hexValue = currentValue;
            if (currentValue.startsWith('rgb')) {
              hexValue = rgbToHex(currentValue);
            } else if (currentValue.startsWith('var(')) {
              const varName = currentValue.slice(4, -1).trim();
              const resolvedValue = computedStyle.getPropertyValue(varName).trim();
              if (resolvedValue.startsWith('rgb')) {
                hexValue = rgbToHex(resolvedValue);
              } else if (resolvedValue && !resolvedValue.startsWith('var(') && resolvedValue.length <= 7) {
                hexValue = resolvedValue;
              }
            }
            
            if (hexValue && hexValue !== '' && hexValue.length <= 7) {
              picker.value = hexValue;
            }
          }
        });
      });
      
    }
  
    window.selectCategoryRewards = selectCategoryRewards;
    window.selectCategoryReward = selectCategoryReward;
    window.showTemplatesForCategory = showTemplatesForCategory;
    window.showSettingsSection = showSettingsSection;
    window.useSavedTemplate = useSavedTemplate;
    window.quickGenerateCode = quickGenerateCode;
    window.applyColorTheme = applyColorTheme;
    window.applyCustomColor = applyCustomColor;
    window.loadCustomColors = loadCustomColors;
    window.resetCustomColors = resetCustomColors;
    window.saveCustomColors = saveCustomColors;
    window.initColorCustomization = initColorCustomization;
    window.updateColorPickerValues = updateColorPickerValues;
    window.clearAllCustomVariables = clearAllCustomVariables;
  })();