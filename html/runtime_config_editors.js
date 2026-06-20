(() => {
  const doc = document;

  function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function rewardFromStructured(obj) {
    if (!obj || typeof obj !== 'object') return null;
    if (obj.money) {
      return { type: 'money', amount: Number(obj.amount) || 0, option: obj.option || 'cash', label: obj.label || '' };
    }
    if (obj.vehicle || obj.model) {
      return { type: 'vehicle', model: obj.model || obj.vehicle || '', label: obj.label || obj.model || '' };
    }
    if (obj.item) {
      return {
        type: 'item',
        item: obj.item,
        amount: Number(obj.amount) || 1,
        label: obj.label || '',
        max_amount: obj.max_amount
      };
    }
    return null;
  }

  function legacyEntryToRewards(entry) {
    if (!entry || typeof entry !== 'object') return [];
    if (Array.isArray(entry)) {
      return entry.map(rewardFromStructured).filter(Boolean);
    }
    const direct = rewardFromStructured(entry);
    if (direct) return [direct];

    const rewards = [];
    Object.entries(entry).forEach(([key, value]) => {
      if (typeof key === 'number') return;
      const k = String(key).toLowerCase();
      if (k === 'cash' || k === 'bank') {
        rewards.push({ type: 'money', amount: Number(value) || 0, option: k, label: k === 'cash' ? 'Cash' : 'Bank' });
      } else if (k === 'vehicle' && typeof value === 'string') {
        rewards.push({ type: 'vehicle', model: value, label: value });
      } else if (typeof value === 'number') {
        rewards.push({
          type: 'item',
          item: key,
          amount: value,
          label: String(key).replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
        });
      }
    });
    return rewards;
  }

  function rewardToStructured(reward, options = {}) {
    const includeMax = !!options.includeMax;
    const includeCategory = !!options.includeCategory;
    const attachCategory = (out) => {
      if (includeCategory && reward.categoryRef) out.category = reward.categoryRef;
      return out;
    };
    if (reward.type === 'money') {
      const out = { money: true, amount: Number(reward.amount) || 0, option: reward.option || 'cash' };
      if (reward.label) out.label = reward.label;
      if (includeMax && reward.max_amount) out.max_amount = Number(reward.max_amount);
      return attachCategory(out);
    }
    if (reward.type === 'vehicle') {
      const out = { vehicle: true, model: reward.model || '' };
      if (reward.label) out.label = reward.label;
      return attachCategory(out);
    }
    if (reward.type === 'item') {
      const out = { item: reward.item || '', amount: Number(reward.amount) || 1 };
      if (reward.label) out.label = reward.label;
      if (includeMax && reward.max_amount) out.max_amount = Number(reward.max_amount);
      return attachCategory(out);
    }
    return null;
  }

  function buildRewardFields(type, data = {}, options = {}) {
    const includeMax = !!options.includeMax;
    const categoryRefField = options.showCategoryRef
      ? `<input type="text" class="input cfg-category-ref" placeholder="Category ref (optional)" value="${escapeHtml(data.categoryRef || '')}">`
      : '';
    if (type === 'money') {
      return `
        <input type="number" class="input cfg-money-amount" min="0" step="1" placeholder="Amount" value="${escapeHtml(data.amount ?? '')}">
        <select class="input cfg-money-option">
          <option value="cash" ${(data.option || 'cash') === 'cash' ? 'selected' : ''}>Cash</option>
          <option value="bank" ${data.option === 'bank' ? 'selected' : ''}>Bank</option>
        </select>
        ${includeMax ? `<input type="number" class="input cfg-max-amount" min="1" placeholder="Max amount" value="${escapeHtml(data.max_amount ?? '')}">` : ''}
        ${categoryRefField}
      `;
    }
    if (type === 'vehicle') {
      return `
        <input type="text" class="input cfg-vehicle-model" placeholder="Vehicle spawn name" value="${escapeHtml(data.model || '')}">
        <input type="text" class="input cfg-vehicle-label" placeholder="Display label" value="${escapeHtml(data.label || '')}">
        ${categoryRefField}
      `;
    }
    return `
      <input type="text" class="input cfg-item-name" placeholder="Item spawn name" value="${escapeHtml(data.item || '')}">
      <input type="text" class="input cfg-item-label" placeholder="Display label (e.g. Water Bottle)" value="${escapeHtml(data.label || '')}">
      <input type="number" class="input cfg-item-amount" min="1" step="1" placeholder="Amount" value="${escapeHtml(data.amount ?? 1)}">
      ${includeMax ? `<input type="number" class="input cfg-max-amount" min="1" placeholder="Max amount" value="${escapeHtml(data.max_amount ?? '')}">` : ''}
      ${categoryRefField}
    `;
  }

  function createRewardRow(reward = {}, options = {}) {
    const row = doc.createElement('div');
    row.className = 'config-reward-row';
    const type = reward.type || 'item';
    row.innerHTML = `
      <select class="input cfg-reward-type">
        <option value="item" ${type === 'item' ? 'selected' : ''}>Item</option>
        <option value="money" ${type === 'money' ? 'selected' : ''}>Money</option>
        <option value="vehicle" ${type === 'vehicle' ? 'selected' : ''}>Vehicle</option>
      </select>
      <div class="cfg-reward-fields">${buildRewardFields(type, reward, options)}</div>
      <button type="button" class="btn btn-sm btn-secondary cfg-remove-reward" title="Remove"><i class="fas fa-times"></i></button>
    `;
    const typeSelect = row.querySelector('.cfg-reward-type');
    const fieldsHost = row.querySelector('.cfg-reward-fields');
    typeSelect.addEventListener('change', () => {
      fieldsHost.innerHTML = buildRewardFields(typeSelect.value, {}, options);
    });
    row.querySelector('.cfg-remove-reward').addEventListener('click', () => row.remove());
    return row;
  }

  function parseRewardRow(row, options = {}) {
    const attachCategory = (reward) => {
      if (options.includeCategory) {
        reward.categoryRef = row.querySelector('.cfg-category-ref')?.value?.trim() || '';
      }
      return reward;
    };
    const type = row.querySelector('.cfg-reward-type')?.value || 'item';
    if (type === 'money') {
      const amount = Number(row.querySelector('.cfg-money-amount')?.value);
      if (!amount || amount <= 0) return null;
      const reward = {
        type: 'money',
        amount,
        option: row.querySelector('.cfg-money-option')?.value || 'cash',
        label: ''
      };
      if (options.includeMax) {
        const max = Number(row.querySelector('.cfg-max-amount')?.value);
        if (max > 0) reward.max_amount = max;
      }
      return attachCategory(reward);
    }
    if (type === 'vehicle') {
      const model = row.querySelector('.cfg-vehicle-model')?.value?.trim();
      if (!model) return null;
      return attachCategory({
        type: 'vehicle',
        model,
        label: row.querySelector('.cfg-vehicle-label')?.value?.trim() || model
      });
    }
    const item = row.querySelector('.cfg-item-name')?.value?.trim();
    if (!item) return null;
    const reward = {
      type: 'item',
      item,
      amount: Number(row.querySelector('.cfg-item-amount')?.value) || 1,
      label: row.querySelector('.cfg-item-label')?.value?.trim() || ''
    };
    if (options.includeMax) {
      const max = Number(row.querySelector('.cfg-max-amount')?.value);
      if (max > 0) reward.max_amount = max;
    }
    return attachCategory(reward);
  }

  function collectRewardsFromList(listEl, options = {}) {
    const rewards = [];
    listEl.querySelectorAll('.config-reward-row').forEach(row => {
      const parsed = parseRewardRow(row, options);
      if (parsed) rewards.push(parsed);
    });
    return rewards;
  }

  function appendRewardsToList(listEl, rewards = [], options = {}) {
    listEl.innerHTML = '';
    rewards.forEach(r => listEl.appendChild(createRewardRow(r, options)));
  }

  function createRotationEntry(rewards = [], index = 0) {
    const entry = doc.createElement('div');
    entry.className = 'config-rotation-entry';
    entry.innerHTML = `
      <div class="config-entry-header">
        <strong>Rotation Entry #${index + 1}</strong>
        <button type="button" class="btn btn-sm btn-secondary cfg-remove-entry"><i class="fas fa-trash"></i> Remove</button>
      </div>
      <div class="config-rewards-list"></div>
      <button type="button" class="btn btn-sm btn-secondary cfg-add-reward"><i class="fas fa-plus"></i> Add Reward</button>
    `;
    const list = entry.querySelector('.config-rewards-list');
    appendRewardsToList(list, rewards);
    entry.querySelector('.cfg-add-reward').addEventListener('click', () => {
      list.appendChild(createRewardRow({ type: 'item' }));
    });
    entry.querySelector('.cfg-remove-entry').addEventListener('click', () => entry.remove());
    return entry;
  }

  function renderDailyRewardsEditor(container, dailyRewards) {
    container.innerHTML = '';
    const list = doc.createElement('div');
    list.className = 'config-rotation-list';
    list.id = 'dailyRotationList';
    container.appendChild(list);

    const entries = Array.isArray(dailyRewards) ? dailyRewards : Object.values(dailyRewards || {});
    if (!entries.length) {
      list.appendChild(createRotationEntry([], 0));
    } else {
      entries.forEach((entry, idx) => {
        list.appendChild(createRotationEntry(legacyEntryToRewards(entry), idx));
      });
    }

    const addBtn = doc.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'btn btn-secondary cfg-add-rotation';
    addBtn.innerHTML = '<i class="fas fa-plus"></i> Add Rotation Entry';
    addBtn.addEventListener('click', () => {
      const count = list.querySelectorAll('.config-rotation-entry').length;
      list.appendChild(createRotationEntry([], count));
    });
    container.appendChild(addBtn);
  }

  function collectDailyRewards(container) {
    const out = [];
    container.querySelectorAll('#dailyRotationList .config-rotation-entry').forEach(entry => {
      const list = entry.querySelector('.config-rewards-list');
      const rewards = collectRewardsFromList(list);
      if (!rewards.length) return;
      const structured = rewards.map(r => rewardToStructured(r)).filter(Boolean);
      if (structured.length === 1) {
        out.push(structured[0]);
      } else if (structured.length > 1) {
        out.push(structured);
      }
    });
    return out;
  }

  function createPrefilledCategoryCard(key, category = {}) {
    const card = doc.createElement('div');
    card.className = 'prefilled-category-card';
    card.dataset.categoryKey = key || '';
    card.innerHTML = `
      <div class="config-entry-header">
        <strong>Category</strong>
        <button type="button" class="btn btn-sm btn-secondary cfg-remove-category"><i class="fas fa-trash"></i></button>
      </div>
      <div class="config-meta-grid">
        <input type="text" class="input cfg-category-key" placeholder="Category ID (e.g. basic_items)" value="${escapeHtml(key || '')}">
        <input type="text" class="input cfg-category-name" placeholder="Display name" value="${escapeHtml(category.name || '')}">
        <input type="text" class="input cfg-category-desc" placeholder="Description" value="${escapeHtml(category.description || '')}">
        <input type="text" class="input cfg-category-icon" placeholder="Icon" value="${escapeHtml(category.icon || '')}">
      </div>
      <div class="config-rewards-list"></div>
      <button type="button" class="btn btn-sm btn-secondary cfg-add-reward"><i class="fas fa-plus"></i> Add Reward</button>
    `;
    const list = card.querySelector('.config-rewards-list');
    const rewards = (category.rewards || []).map(r => {
      const parsed = rewardFromStructured(r);
      if (parsed && r.max_amount) parsed.max_amount = r.max_amount;
      return parsed;
    }).filter(Boolean);
    appendRewardsToList(list, rewards, { includeMax: true });
    card.querySelector('.cfg-add-reward').addEventListener('click', () => {
      list.appendChild(createRewardRow({ type: 'item' }, { includeMax: true }));
    });
    card.querySelector('.cfg-remove-category').addEventListener('click', () => card.remove());
    return card;
  }

  function createQuickTemplateCard(key, template = {}) {
    const card = doc.createElement('div');
    card.className = 'prefilled-template-card';
    card.dataset.templateKey = key || '';
    card.innerHTML = `
      <div class="config-entry-header">
        <strong>Quick Template</strong>
        <button type="button" class="btn btn-sm btn-secondary cfg-remove-template"><i class="fas fa-trash"></i></button>
      </div>
      <div class="config-meta-grid">
        <input type="text" class="input cfg-template-key" placeholder="Template ID" value="${escapeHtml(key || '')}">
        <input type="text" class="input cfg-template-name" placeholder="Name" value="${escapeHtml(template.name || '')}">
        <input type="text" class="input cfg-template-desc" placeholder="Description" value="${escapeHtml(template.description || '')}">
        <input type="text" class="input cfg-template-icon" placeholder="Icon" value="${escapeHtml(template.icon || '')}">
        <input type="text" class="input cfg-template-category" placeholder="Category tag" value="${escapeHtml(template.category || '')}">
      </div>
      <div class="config-rewards-list"></div>
      <button type="button" class="btn btn-sm btn-secondary cfg-add-reward"><i class="fas fa-plus"></i> Add Reward</button>
    `;
    const list = card.querySelector('.config-rewards-list');
    const rewards = (template.rewards || []).map(r => {
      const parsed = rewardFromStructured(r);
      if (parsed && r.category) parsed.categoryRef = r.category;
      return parsed;
    }).filter(Boolean);
    appendRewardsToList(list, rewards, { includeCategory: true });
    card.querySelector('.cfg-add-reward').addEventListener('click', () => {
      list.appendChild(createRewardRow({ type: 'item' }, { includeCategory: true }));
    });
    card.querySelector('.cfg-remove-template').addEventListener('click', () => card.remove());
    return card;
  }

  function renderPrefilledEditor(container, prefilled = {}) {
    container.innerHTML = '';
    const data = prefilled.PreFilledRewards || prefilled;

    const catSection = doc.createElement('div');
    catSection.className = 'prefilled-editor-section';
    catSection.innerHTML = '<h4 class="config-section-title">Reward Categories</h4>';
    const catList = doc.createElement('div');
    catList.className = 'prefilled-categories-list';
    catList.id = 'prefilledCategoriesList';
    Object.entries(data.reward_categories || {}).forEach(([key, cat]) => {
      catList.appendChild(createPrefilledCategoryCard(key, cat));
    });
    catSection.appendChild(catList);
    const addCatBtn = doc.createElement('button');
    addCatBtn.type = 'button';
    addCatBtn.className = 'btn btn-secondary cfg-add-category';
    addCatBtn.innerHTML = '<i class="fas fa-plus"></i> Add Category';
    addCatBtn.addEventListener('click', () => catList.appendChild(createPrefilledCategoryCard('')));
    catSection.appendChild(addCatBtn);
    container.appendChild(catSection);

    const tplSection = doc.createElement('div');
    tplSection.className = 'prefilled-editor-section';
    tplSection.innerHTML = '<h4 class="config-section-title">Quick Templates</h4>';
    const tplList = doc.createElement('div');
    tplList.className = 'prefilled-templates-list';
    tplList.id = 'prefilledTemplatesList';
    Object.entries(data.quick_templates || {}).forEach(([key, tpl]) => {
      tplList.appendChild(createQuickTemplateCard(key, tpl));
    });
    tplSection.appendChild(tplList);
    const addTplBtn = doc.createElement('button');
    addTplBtn.type = 'button';
    addTplBtn.className = 'btn btn-secondary cfg-add-template';
    addTplBtn.innerHTML = '<i class="fas fa-plus"></i> Add Template';
    addTplBtn.addEventListener('click', () => tplList.appendChild(createQuickTemplateCard('')));
    tplSection.appendChild(addTplBtn);
    container.appendChild(tplSection);

    const aiSection = doc.createElement('div');
    aiSection.className = 'prefilled-editor-section';
    aiSection.innerHTML = `
      <h4 class="config-section-title">AI Code Templates</h4>
      <p class="input-help">Pattern lists used by Shadow for code generation styles.</p>
      <textarea id="cfgAICodeTemplatesJson" class="input runtime-json-editor" rows="12"></textarea>
    `;
    container.appendChild(aiSection);
    const aiTemplates = prefilled.AICodeTemplates || {};
    aiSection.querySelector('#cfgAICodeTemplatesJson').value = JSON.stringify(aiTemplates, null, 2);
  }

  function collectPrefilled(container) {
    const reward_categories = {};
    container.querySelectorAll('#prefilledCategoriesList .prefilled-category-card').forEach(card => {
      const key = card.querySelector('.cfg-category-key')?.value?.trim();
      if (!key) return;
      const rewards = collectRewardsFromList(card.querySelector('.config-rewards-list'), { includeMax: true })
        .map(r => rewardToStructured(r, { includeMax: true }))
        .filter(Boolean);
      reward_categories[key] = {
        name: card.querySelector('.cfg-category-name')?.value?.trim() || key,
        description: card.querySelector('.cfg-category-desc')?.value?.trim() || '',
        icon: card.querySelector('.cfg-category-icon')?.value?.trim() || '',
        rewards
      };
    });

    const quick_templates = {};
    container.querySelectorAll('#prefilledTemplatesList .prefilled-template-card').forEach(card => {
      const key = card.querySelector('.cfg-template-key')?.value?.trim();
      if (!key) return;
      const rewards = collectRewardsFromList(card.querySelector('.config-rewards-list'))
        .map(r => rewardToStructured(r, { includeCategory: true }))
        .filter(Boolean);
      quick_templates[key] = {
        name: card.querySelector('.cfg-template-name')?.value?.trim() || key,
        description: card.querySelector('.cfg-template-desc')?.value?.trim() || '',
        icon: card.querySelector('.cfg-template-icon')?.value?.trim() || '',
        category: card.querySelector('.cfg-template-category')?.value?.trim() || '',
        rewards
      };
    });

    let AICodeTemplates = {};
    try {
      AICodeTemplates = JSON.parse(container.querySelector('#cfgAICodeTemplatesJson')?.value || '{}');
    } catch (_) {
      AICodeTemplates = {};
    }

    return {
      PreFilledRewards: { reward_categories, quick_templates },
      AICodeTemplates
    };
  }

  function createFilterWordRow(word = '') {
    const row = doc.createElement('div');
    row.className = 'filter-word-row';
    row.innerHTML = `
      <input type="text" class="input filter-word-input" value="${escapeHtml(word)}" placeholder="Word">
      <button type="button" class="btn btn-sm btn-secondary cfg-remove-word"><i class="fas fa-times"></i></button>
    `;
    row.querySelector('.cfg-remove-word').addEventListener('click', () => row.remove());
    return row;
  }

  function createFilterCategoryCard(category, words = []) {
    const card = doc.createElement('div');
    card.className = 'content-filter-card';
    card.innerHTML = `
      <div class="config-entry-header">
        <input type="text" class="input filter-category-name" value="${escapeHtml(category)}" placeholder="Category name">
        <button type="button" class="btn btn-sm btn-secondary cfg-remove-filter-category"><i class="fas fa-trash"></i></button>
      </div>
      <div class="filter-words-list"></div>
      <div class="filter-add-word-row">
        <input type="text" class="input filter-new-word" placeholder="Add word">
        <button type="button" class="btn btn-sm btn-secondary cfg-add-word">Add</button>
      </div>
    `;
    const wordsList = card.querySelector('.filter-words-list');
    words.forEach(w => wordsList.appendChild(createFilterWordRow(w)));
    const addWord = () => {
      const input = card.querySelector('.filter-new-word');
      const val = input?.value?.trim();
      if (!val) return;
      wordsList.appendChild(createFilterWordRow(val));
      input.value = '';
    };
    card.querySelector('.cfg-add-word').addEventListener('click', addWord);
    card.querySelector('.filter-new-word').addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); addWord(); }
    });
    card.querySelector('.cfg-remove-filter-category').addEventListener('click', () => card.remove());
    return card;
  }

  function renderContentFilterEditor(container, badWords) {
    container.innerHTML = '';
    const list = doc.createElement('div');
    list.className = 'content-filter-grid';
    list.id = 'contentFilterCategories';
    Object.entries(badWords || {}).forEach(([category, words]) => {
      list.appendChild(createFilterCategoryCard(category, words || []));
    });
    container.appendChild(list);
    const addBtn = doc.createElement('button');
    addBtn.type = 'button';
    addBtn.className = 'btn btn-secondary cfg-add-filter-category';
    addBtn.innerHTML = '<i class="fas fa-plus"></i> Add Category';
    addBtn.addEventListener('click', () => {
      list.appendChild(createFilterCategoryCard('new_category', []));
    });
    container.appendChild(addBtn);
  }

  function collectContentFilter(container) {
    const badWords = {};
    container.querySelectorAll('#contentFilterCategories .content-filter-card').forEach(card => {
      const category = card.querySelector('.filter-category-name')?.value?.trim();
      if (!category) return;
      const words = [];
      card.querySelectorAll('.filter-word-row .filter-word-input').forEach(input => {
        const val = input.value.trim();
        if (val) words.push(val);
      });
      badWords[category] = words;
    });
    return { BadWords: badWords };
  }

  window.RuntimeConfigEditors = {
    renderDailyRewardsEditor,
    collectDailyRewards,
    renderPrefilledEditor,
    collectPrefilled,
    renderContentFilterEditor,
    collectContentFilter,
    legacyEntryToRewards,
    rewardToStructured
  };
})();
