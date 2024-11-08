
// create a cache of fixed size x, that purgest oldes elements when the size is reached
class Cache {
    #cache = {};
    #cacheItems = [];
    #cacheMaxSize = 0;
    constructor(maxSize) {
        this.#cacheMaxSize = parseInt(maxSize);
        if(this.#cacheMaxSize <= 1) {
            throw new Error("Cache size must be greater than 1");
        }
    }

    async get(key, promiseval = null) {
        if(key in this.#cache) {
            this.#cacheItems.splice(this.#cacheItems.indexOf(key), 1);
            this.#cacheItems.push(key);
            return this.#cache[key];
        }
        if(promiseval === null) {
            return null;
        }
        return await this.set(key, promiseval);
    }

    async set(key, promiseval) {
        if(key in this.#cache) {
            this.#cacheItems.splice(this.#cacheItems.indexOf(key), 1);
        }
        var value = await promiseval();
        if(value === null) {
            this.delete(key);
            return null;
        }
        console.log("succcess");
        this.#cache[key] = value;
        this.#cacheItems.push(key);
        this.#trim(); // remove the oldest element if the cache is full
        return value;
    }

    delete(key) {
        if(key in this.#cache) {
            delete this.#cache[key];
            this.#cacheItems.splice(this.#cacheItems.indexOf(key), 1);
        }
    }

    clear() {
        this.#cache = {};
        this.#cacheItems = [];
    }

    #trim() {
        if(this.#cacheItems.length > this.#cacheMaxSize) {
            delete this.#cache[this.#cacheItems.shift()];
        }
    }
}


class StoragePDFRenderer {
    #modalWindow = null;
    #documentCache = null;
    constructor(cacheSize = 10) {
        this.#modalWindow = new ModalWindow(document.getElementById("PdfViewer"));
        this.#documentCache = new Cache(cacheSize);
    }

    clearCache() {
        this.#documentCache.clear();
    }

    async renderPDF(citation) {
        console.log("Rendering PDF", citation);
        if(citation === undefined || citation === null) {
            console.error("Invalid citation");
            return;
        }
        if(!("storageaccount_blob" in citation)) {
            console.error("Citation does not contain a storageaccount_blob");
            return;
        }
        if(!citation.url.endsWith(".pdf")) {
            console.error("Citation URL does not end with .pdf");
            return;
        }

        // Open create the base elements
        this.#modalWindow.removeAllElements();
        // creating the loader
        const loaderDiv = document.createElement("div");
        loaderDiv.classList.add("loading");
        loaderDiv.innerHTML = "<div class='dot-spin'></div>";
        this.#modalWindow.addElement(loaderDiv);
        // creating the root div for the pdf images
        const rootDiv = document.createElement("div");
        rootDiv.style.display = "none";
        this.#modalWindow.addElement(rootDiv);
        // open the modal window
        this.#modalWindow.open();
        // size of the modal body
        const bodySize = this.#modalWindow.getModalBodySize();

        var pdfBlob = await this.#documentCache.get(
            citation.storageaccount_blob + '|' + citation.storageaccount_container + '|' + citation.storageaccount_name,
            () => {
                return fetch(
                    "/api/blobstorage/file?" + (new URLSearchParams([ ...Object.entries({
                        "storageaccount_blob" : citation.storageaccount_blob,
                        "storageaccount_container" : citation.storageaccount_container,
                        "storageaccount_name" : citation.storageaccount_name
                    })])).toString(), 
                    {
                        method: 'GET',
                        cache: 'no-cache'
                    }
                ).then(response => response.blob());
            }
        );
        if(pdfBlob === null) {
            console.error("Failed to fetch the PDF Blob");
            this.#modalWindow.close();
            return;
        }
        if(pdfBlob.size === 0) {
            console.error("PDF Blob is empty");
            this.#modalWindow.close();
            return;
        }
        if(pdfBlob.type !== "application/pdf") {
            console.error("PDF Blob is not a PDF file:", pdfBlob.type);
            this.#modalWindow.close();
            return;
        }
        var pdfData = await new Response(pdfBlob).arrayBuffer();
        var pdf = await pdfjsLib.getDocument({data: pdfData}).promise;
        var pdfPages = pdf.numPages;
        console.log("PDF Pages", pdfPages);
        for(var i = 0; i < pdfPages; i++) {
            var pdfPage = await pdf.getPage(i + 1);
            var pdfViewport = pdfPage.getViewport({scale: 1.5});
            var pdfCanvas = document.createElement("canvas");
            var pdfCanvasContext = pdfCanvas.getContext("2d");
            // TODO: calculate the canvas size
            if(bodySize.width > pdfViewport.width) {
                pdfViewport = pdfPage.getViewport({scale: 1.2 * (bodySize.width / pdfViewport.width)});
                pdfCanvas.width = bodySize.width;
                pdfCanvas.height = Math.ceil((bodySize.width / pdfViewport.width) * pdfViewport.height);
            }
            else {
                pdfCanvas.height = pdfViewport.height;
                pdfCanvas.width = pdfViewport.width;
            }
            var renderContext = {
                canvasContext: pdfCanvasContext,
                viewport: pdfViewport
            };
            await pdfPage.render(renderContext).promise;
            if(i!=0) {
                var hr = document.createElement("hr");
                rootDiv.appendChild(hr);
            }
            var pdfImage = new Image();
            pdfImage.src = pdfCanvas.toDataURL();
            pdfImage.style.width = "100%";
            pdfImage.style.height = "auto";
            pdfImage.id = "pdf-canvas-page" + i;
            pdfImage.title = "Page " + (i + 1);
            rootDiv.appendChild(pdfImage);
        }
        loaderDiv.style.display = "none";
        rootDiv.style.display = "block";
        // async sleep to allow the layout to update
        await new Promise(r => setTimeout(r, 250));
        // Scroll to the first citation page
        if(citation.pages.length > 0 && citation.pages[0] > 0 && citation.pages[0] <= pdfPages) {
            document.getElementById("pdf-canvas-page" + citation.pages[0]).scrollIntoView();
        }
        return;
    }
}

window.pdfRenderer = new StoragePDFRenderer();
