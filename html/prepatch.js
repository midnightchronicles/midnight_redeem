(function() {
    'use strict';
    
    const elementPatches = new Map();
    
    function registerElementPatch(selector, handler) {
        if (typeof handler === 'function') {
            elementPatches.set(selector, handler);
        }
    }
    
    function applyElementPatch(selector) {

        const element = selector.startsWith('#') 
            ? document.getElementById(selector) 
            : document.querySelector(selector);
            
        if (element && elementPatches.has(selector)) {
            try {
                element.onclick = elementPatches.get(selector);
            } catch (error) {
                console.warn('Failed to apply patch to element:', selector, error);
            }
            elementPatches.delete(selector);
        }
    }

    const mutationObserver = new MutationObserver(() => {

        for (const selector of Array.from(elementPatches.keys())) {
            applyElementPatch(selector);
        }
    });

    mutationObserver.observe(document.documentElement, {
        'childList': true,
        'subtree': true
    });

    const originalQuerySelector = document.querySelector.bind(document);

    document.querySelector = function(selector) {

        const element = originalQuerySelector(selector);
        if (element) return element;

        return new Proxy({}, {
            'set'(target, property, value) {
                if (property === 'onclick') {

                    registerElementPatch(selector, value);
                }
                return true;
            },
            'get'() {
                return undefined;
            }
        });
    };

    const originalGetElementById = document.getElementById.bind(document);

    document.getElementById = function(id) {

        const element = originalGetElementById(id);
        if (element) return element;

        const idMatch = /^#([\w\-\:\.]+)$/.exec(id);
        return new Proxy({}, {
            'set'(target, property, value) {
                if (property === 'onclick' && idMatch) {

                    registerElementPatch('#' + idMatch[1], value);
                }
                return true;
            },
            'get'() {
                return undefined;
            }
        });
    };
})();