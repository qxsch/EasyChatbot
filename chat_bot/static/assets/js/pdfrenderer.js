
class StoragePDFRenderer {
    #modalWindow = null;
    constructor() {
        this.#modalWindow = new ModalWindow(document.getElementById("PdfViewer"));
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

        var pdfBlob = await fetch(
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
        var pdfData = await new Response(pdfBlob).arrayBuffer();
        var pdf = await pdfjsLib.getDocument({data: pdfData}).promise;
        var pdfPages = pdf.numPages;
        console.log("PDF Pages", pdfPages);
        this.#modalWindow.removeAllElements();
        for(var i = 0; i < pdfPages; i++) {
            var pdfPage = await pdf.getPage(i + 1);
            var pdfViewport = pdfPage.getViewport({scale: 1.5});
            var pdfCanvas = document.createElement("canvas");
            var pdfCanvasContext = pdfCanvas.getContext("2d");
            // TODO: calculate the canvas size
            pdfCanvas.height = pdfViewport.height;
            pdfCanvas.width = pdfViewport.width;
            var renderContext = {
                canvasContext: pdfCanvasContext,
                viewport: pdfViewport
            };
            await pdfPage.render(renderContext).promise;
            var pdfImage = new Image();
            pdfImage.src = pdfCanvas.toDataURL();
            pdfImage.style.width = "100%";
            pdfImage.style.height = "auto";
            pdfImage.id = "pdf-canvas-page" + i;
            this.#modalWindow.addElement(pdfImage);
        }
        // Open the modal window
        this.#modalWindow.open();
        // Scroll to the first citation page
        if(citation.pages.length > 0 && citation.pages[0] > 0 && citation.pages[0] <= pdfPages) {
            document.getElementById("pdf-canvas-page" + citation.pages[0]).scrollIntoView();
        }
        return;
    }
}

window.pdfRenderer = new StoragePDFRenderer();
